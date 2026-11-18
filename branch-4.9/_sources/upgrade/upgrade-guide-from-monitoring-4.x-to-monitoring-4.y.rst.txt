======================================================================
Upgrade Guide - ScyllaDB Monitoring 4.x.a to ScyllaDB Monitoring 4.y.b
======================================================================

This document is a step by step procedure for upgrading ScyllaDB Monitoring Stack from version 4.x.a to 4.y.b, for example, between 4.0.0 to 4.0.1.

Upgrade Procedure
=================

We recommend installing the new release next to the old one, running both in parallel, and making sure it is working as expected before uninstalling the old version.

Change to the directory you want to install the new Monitoring stack.
Download the latest release:
You can download the .zip or the .tar.

Install 4.y.b (The new version)
-------------------------------

.. code-block:: bash

                wget -L https://github.com/scylladb/scylla-monitoring/archive/scylla-monitoring-4.y.b.zip
                unzip scylla-monitoring-4.y.b.zip
                cd scylla-monitoring-scylla-monitoring-4.y.b/

Replace “y” with the new minor release number, for example, 4.0.1.zip

.. note::
    For versions 4.7.* and above, use the format `4.7.*.zip`, for example:

    .. code-block:: bash

        wget -L https://github.com/scylladb/scylla-monitoring/archive/4.7.1.zip
        unzip 4.7.b.zip
        cd scylla-monitoring-4.7.b/

Setting the server's files
--------------------------

Copy the target files ``scylla_servers.yml`` and ``scylla_manager_servers.yml`` from the version that is already installed.

.. code-block:: bash

                cp /path/to/monitoring/4.x.a/prometheus/scylla_servers.yml prometheus/
                cp /path/to/monitoring/4.x.a/prometheus/scylla_manager_servers.yml.yml prometheus/

Validate the port numbers
^^^^^^^^^^^^^^^^^^^^^^^^^
ScyllaDB-monitoring reads from ScyllaDB itself, from node_exporter for OS-related metrics, and from the ScyllaDB Manager agent.

Almost always, those targets use their default ports, and all share the same IP.
If you use the default port number, we recommend using the target file without ports and letting ScyllaDB monitoring add the default port number.
If the ScyllaDB Manager agent and node_exporter are running next to ScyllaDB on the same host (the default installation), use one target file for scylla_server, and the ScyllaDB monitoring will use that file with the correct ports for each target.

.. caution::

   As of SyllaDB Monitoring 4.5, Specifying the node_exporter file (the -n flag) with the wrong ports will prevent ScyllaDB Monitoring from reading the metrics.

Validate the new version is running the correct version
-------------------------------------------------------

Run:

.. code-block:: bash

                ./start-all.sh --version

To validate the Scylla-Monitoring version.


Validate the version installed correctly
----------------------------------------

To validate that the Monitoring stack starts correctly, first in parallel to the current (4.x.a) stack.

.. code-block:: bash

                ./start-all.sh -p 9091 -g 3001 -m 9095

Browse to ``http://{ip}:9091``
And check the Grafana dashboard

Note that we are using different port numbers for Grafana, Prometheus, and the Alertmanager.

.. caution::

   Important: do not use the local dir flag when testing!

When you are satisfied with the data in the dashboard, you can shut down the containers.

.. caution::

   Important: Do not kill the 4.x.a version that is currently running.

Killing the new 4.y.b Monitoring stack in testing mode
------------------------------------------------------

Use the following command to kill the containers:

.. code-block:: bash

                ./kill-all.sh -p 9091 -g 3001 -m 9095

You can start and stop the new 4.y.b version while testing.

Move to version 4.y.b (the new version)
---------------------------------------

Note: migrating will cause a few seconds of blackout in the system.

We assume that you are using external volume to store the metrics data.

Kill all containers
^^^^^^^^^^^^^^^^^^^

At this point you have two monitoring stacks running side by side, you should kill both before
continuing.

Kill the newer version that runs in testing mode by following the instructions on how to `Killing the new 4.y.b Monitoring stack in testing mode`_
in the previous section

kill the older 4.x.a version containers by running:

.. code-block:: bash

                ./kill-all.sh

Start version 4.y.b in normal mode


From the new root of the `scylla-monitoring-scylla-monitoring-4.y.b` run

.. code-block:: bash

                ./start-all.sh -d /path/to/data/dir


Point your browser to ``http://{ip}:3000`` and see that the data is there.

Rollback to version 4.x.a
-------------------------


To rollback during the testing mode, follow `Killing the new 4.y.b Monitoring stack in testing mode`_ as explained previously
and the system will continue to operate normally.

To rollback to version 4.x.a after you completed the moving to version 4.y.b (as shown above).
Run:

.. code-block:: bash

                ./kill-all.sh
                cd /path/to/scylla-grafana-4.x.a/
                ./start-all.sh -d /path/to/data/dir

Related Links
=============

* `ScyllaDB Monitoring </operating-scylla/monitoring/>`_
* :doc:`Upgrade</upgrade/index>`
