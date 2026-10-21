Configure the Stack from One File
=================================

Instead of passing command-line flags to ``start-all.sh``, you can describe the whole monitoring stack in one YAML file.
``scylla_monitoring_config.py``, the *watcher*, reads the file, applies it, and applies it again whenever it changes.

The file holds everything the stack needs: the targets, the alert rules, the Alertmanager configuration,
the Grafana settings, the storage directories, TLS, and systemd drop-ins for host services such as node_exporter.
The watcher generates the derived files from it, starts the stack, and on a later change runs only what
that change needs: a change to the targets needs no restart, a change to the alert rules reloads Prometheus,
and a new Grafana password is set in place.

Requirements
------------

* Python 3, with ``PyYAML`` (``python3-yaml``) and ``jsonschema`` 3.2 or later (``python3-jsonschema``).
* The watcher runs as a regular user who is a member of the ``docker`` group.
* TLS certificates and systemd drop-ins need root. The watcher runs ``scylla-monitoring-root.sh`` for them with ``sudo -n``.
  Install the script root-owned and let the watcher's user run it, and only it, for example:

  .. code-block:: shell

     sudo install -o root -g root -m 755 scylla-monitoring-root.sh /usr/local/sbin/
     echo 'scylla ALL=(root) NOPASSWD: /usr/local/sbin/scylla-monitoring-root.sh' | sudo tee /etc/sudoers.d/scylla-monitoring

  Replace ``scylla`` with the watcher's user. Without the ``tls`` and ``systemd`` sections, the watcher does not need root.

The Configuration File
----------------------

``scylla-monitoring.schema.json``, in the root of the monitoring directory, defines the file.
The description of each field names the ``start-all.sh`` flag it replaces and its default.
``scylla-monitoring.example.yaml`` is a complete, commented example:

.. literalinclude:: ../../../scylla-monitoring.example.yaml
   :language: yaml

``version``, ``generation``, ``stack`` and ``targets`` are required. A missing optional section keeps the
``start-all.sh`` default: without ``tls`` no traefik runs, and without ``systemd`` the host's units are left as they are.

``stack.extra_flags`` takes any other ``start-all.sh`` flag, in ``start-all.sh`` syntax. A flag there takes
precedence over the same option derived from the rest of the file. The options the watcher sets from the file itself
(the targets, rule and Alertmanager files, ``--target-directory``, ``--vector-search``, ``--vector-store``,
``--cluster-label``, ``--archive``, ``--compose`` and ``-h``) are rejected in ``extra_flags``.

Writing the File
^^^^^^^^^^^^^^^^

* Always write the whole file, and replace it atomically: write a temporary file in the same directory and rename it into place.
* The file holds secrets (the Grafana admin password, the CQL password and the TLS private key). Keep it ``0600``, owned by the watcher's user.
* Set ``generation`` to a new value on every write. The watcher reports it back in the status file, so you know when your change is applied.
* The watcher ignores fields it does not know. With ``--strict``, an unknown field rejects the file.

Running the Watcher
-------------------

.. code-block:: shell

   scylla_monitoring_config.py check|apply|run --config-file FILE --monitoring-dir DIR [options]

* ``check`` validates the file, renders the derived files into a temporary directory and prints the ``start-all.sh`` command line,
  with the secrets masked. It changes nothing, so it is safe to run next to a running watcher.
* ``apply`` applies the file once. ``--force`` applies it as a first apply, restarting the whole stack.
* ``run`` applies the file on start, then checks it every ``--poll-interval`` seconds (30) and applies it when it changes.
  On start, it checks that the stack is up; when it is not (for example, after a reboot), the file is applied whole.
  Until the file exists, it waits and changes nothing.

Options:

**--config-file path** The configuration file. It can be given more than once; the watcher watches every path and applies the one that changed last.

**--monitoring-dir path** The monitoring directory, where ``start-all.sh`` is. The watcher runs the start scripts from it.

**--compose** Run the stack with Docker Compose instead of ``start-all.sh``. See :doc:`Docker Compose <docker-compose>`.

**--strict** Reject fields the schema does not define.

**--auto-revert** When an apply fails, apply the previous configuration again.

**--state-dir path** Where the last applied configuration and the status are kept (default: ``<monitoring-dir>/config-state``).

**--staging-dir path** Where the derived files are generated (default: ``<monitoring-dir>/config-build``).

**--cert-dir path** Where the TLS certificates are installed (default: ``/etc/scylla-monitoring/certs``).

**--root-helper path** The root helper (default: ``<monitoring-dir>/scylla-monitoring-root.sh``).

**--health-timeout seconds** How long to wait for the components to become ready after an apply (default: 180).

**--poll-interval seconds** How often ``run`` checks the file (default: 30).

As a systemd Service
^^^^^^^^^^^^^^^^^^^^

Run the watcher as a service, for example with ``/etc/systemd/system/scylla-monitoring-config.service``:

.. code-block:: ini

   [Unit]
   Description=Configure the monitoring stack from its config file
   After=docker.service network-online.target
   Wants=network-online.target
   PartOf=docker.service

   [Service]
   User=scylla
   WorkingDirectory=/opt/scylla-monitoring
   ExecStart=/usr/bin/python3 /opt/scylla-monitoring/scylla_monitoring_config.py run --monitoring-dir /opt/scylla-monitoring --config-file /etc/scylla-monitoring/scylla-monitoring.yaml --root-helper /usr/local/sbin/scylla-monitoring-root.sh
   Restart=on-failure

   [Install]
   WantedBy=multi-user.target

The watcher's user needs to read the config file. It writes the status next to the file when it can write to that directory,
and always in the state directory. When the data directories are on a separate disk, add ``RequiresMountsFor=<data dir>`` in a drop-in.

* ``systemctl stop scylla-monitoring-config`` stops the watcher; ``./kill-all.sh`` (or ``docker compose down``) then stops the containers.
* ``systemctl start scylla-monitoring-config`` starts the watcher, which brings the stack up.

How Changes Are Applied
-----------------------

Each apply validates the file, renders the derived files and checks them with ``promtool`` and ``amtool``.
If the file or a derived file is invalid, the running stack is left as it is, and the status file says why.
Otherwise the watcher compares each section with the last applied configuration and runs what the changed sections need:

========================================================== ==================================================
Change                                                     What runs
========================================================== ==================================================
``targets``                                                nothing; Prometheus reads the new targets
``alert_rules``                                            Prometheus reload
``alertmanager_config``                                    Alertmanager reload
``cluster``                                                the Prometheus configuration is generated again, then reloaded
``grafana.admin_password``                                 the password is set in Grafana
``grafana.datasource``                                     the data source is written, then Grafana restarts
``tls`` certificates                                       the certificates are installed, then traefik reloads them
``tls.enabled``, ``tls.listen_ip``                         traefik starts, restarts or is removed
``systemd``                                                the unit's drop-in is written or removed, then the unit restarts
``stack``, ``storage``, ``prometheus``, other ``grafana``  the stack restarts
========================================================== ==================================================

Adding or removing ``alert_rules``, ``alertmanager_config`` or ``targets.vector_search`` also restarts the stack.

A ``systemd`` entry maps a unit name to the content of a drop-in, written as
``/etc/systemd/system/<unit>.d/50-scylla-monitoring.conf``. The watcher owns only that file.
For example, the node_exporter unit installed by the ScyllaDB images ends its command line with ``$NODE_EXPORTER_ARGS``,
so a drop-in can set its arguments:

.. code-block:: yaml

   systemd:
     node-exporter.service: |
       [Service]
       Environment=NODE_EXPORTER_ARGS=--web.listen-address=127.0.0.1:9100

With ``tls.enabled``, traefik serves the stack on ``tls.listen_ip`` with mutual TLS.
Set ``stack.bind_address`` to ``127.0.0.1`` as well, so traefik is the only way in.

The Status File
---------------

After each apply, the watcher writes ``status.json`` in the state directory, and ``scylla-monitoring.status.json``
next to each config file:

.. code-block:: json

   {"generation": "9f2c", "state": "applied", "time": "2026-10-20T10:00:00Z"}
   {"generation": "a1b3", "state": "rejected", "error": "alert_rules: ...", "time": "2026-10-20T10:05:00Z"}

* ``applied``: the stack runs the configuration of ``generation``.
* ``rejected``: the file is invalid; the stack still runs ``applied_generation``.
* ``failed``: the apply failed; the stack is left as the failed apply left it, for inspection. The next apply runs every action, as a first apply does.
* ``reverted``: the apply failed and, with ``--auto-revert``, the previous configuration was applied again.

Error messages name the section and position, without the values, since the file holds secrets.

.. note::

   ``start-all.sh`` and the start scripts still read ``env.sh`` from the monitoring directory, and what it sets can override the file.
   The watcher logs a warning when ``env.sh`` exists.
