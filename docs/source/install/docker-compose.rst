Using Docker Compose
====================

Scylla-Monitoring Stack is container-based.
You can start and stop the Scylla Monitoring Stack with the `start-all.sh` and `kill-all.sh` scripts.

Docker Compose is an alternative way to run the same stack. ``make_compose.py`` takes the ``start-all.sh``
command-line options and writes a ``docker-compose.yml`` file, an ``.env`` file and the configuration files
for the stack that ``start-all.sh`` would run with those options.

.. warning::

    *docker compose up* **and** *start-all.sh* are two **alternative** ways to launch Scylla Monitoring Stack.
    You should use **one** method, **not both**. Run ``./kill-all.sh`` before switching from ``start-all.sh`` to Docker Compose.

Prerequisite
------------

* ``docker`` with the ``docker compose`` plugin.
* Python 3 with ``PyYAML`` (``python3-yaml``). Only Docker Compose needs Python; ``start-all.sh`` does not.

Generate the Compose File
-------------------------

Run ``make_compose.py`` from the monitoring directory, with the options you would pass to ``start-all.sh``, for example:

.. code-block:: shell

   ./make_compose.py -d /path/to/prometheus/data -v 2025.3 -s prometheus/scylla_servers.yml

``make_compose.py`` accepts every ``start-all.sh`` option (see :doc:`The start-all.sh script <start-all>`),
reads ``env.sh`` the same way, and rejects an option it cannot express in Docker Compose. It writes:

* ``docker-compose.yml``, with one service per container ``start-all.sh`` runs, with the same container names, so ``kill-all.sh`` finds them.
* ``.env`` (``0600``), with the secrets only: the Grafana admin password, the Grafana renderer token and the Datadog API key.
* The Prometheus configuration, the Grafana data source and dashboard provisioning, and the Loki, Alloy or Promtail configuration.

Then start the stack:

.. code-block:: shell

   docker compose up -d

Or let ``make_compose.py`` run it, with ``--compose``:

.. code-block:: shell

   ./make_compose.py --compose -d /path/to/prometheus/data -v 2025.3

``./start-all.sh --compose [options]`` does the same.

All the containers start in parallel, so the stack is up sooner than with ``start-all.sh``.

Running ``make_compose.py`` again overwrites the generated files. Changing an option and running it again with ``--compose``
recreates only the containers whose definition or configuration files changed. Keep your changes in the options, not in the generated files.

Options
-------

**--compose** Also run ``docker compose up -d --remove-orphans``.

**--traefik** Add traefik, which serves the stack over TLS with mutual authentication.
Set ``PRIVATE_IP`` (the address traefik listens on) and ``CERT_DIR`` (the directory with ``server.crt``, ``server.key`` and ``rootCA.crt``)
in the environment. ``--traefik`` needs ``-A 127.0.0.1``, so traefik is the only way in, and cannot be used with ``-l``.
With ``--compose``, traefik starts after the rest of the stack, once ``start-traefik.sh --check`` finds no proxied port
reachable outside loopback.

**--stack id** Run a secondary stack. Its Compose project is ``scylla-monitoring-stack<id>``, written to ``docker-compose.stack<id>.yml``
and ``.env.stack<id>``, so it does not replace the first one. Pass ``-f docker-compose.stack<id>.yml --env-file .env.stack<id>``
to ``docker compose`` to act on it.

``-D`` and the per-container ``--limit``, ``--volume`` and ``--param`` options are translated to Docker Compose settings, for example:

.. code-block:: shell

   ./make_compose.py --limit prometheus,--memory=8g --limit grafana,--cpus=1

Start and Stop
--------------

To stop the stack, run ``docker compose down`` (or ``./kill-all.sh``) in the monitoring directory.
To start it again, run ``docker compose up -d``.

The Configuration File
----------------------

``scylla_monitoring_config.py --compose`` applies a configuration file to a stack run with Docker Compose.
See :doc:`Configure the Stack from One File <config-file>`.

.. note::

   ``make-compose.sh`` is deprecated. Use ``make_compose.py``.
