==============================================================
Upgrade Guide - Scylla Monitoring 3.x to Scylla Monitoring 4.y
==============================================================

This document is a step by step procedure for upgrading `Scylla Monitoring Stack </operating-scylla/monitoring/3.0>`_ from version 3.x to 4.y, for example, between 3.9 to 4.0.0.

Upgrade Procedure
=================

We recommend installing the new release next to the old one. You can run both monitoring stacks in parallel, ensuring it is working as expected before uninstalling the old version.

Change to the directory you want to install the new Monitoring stack.
Download the latest release in the .zip or .tar format.

Install 4.y (The new version)
-----------------------------

.. code-block:: bash

                wget -L https://github.com/scylladb/scylla-monitoring/archive/scylla-monitoring-4.y.zip
                unzip scylla-monitoring-4.y.zip
                cd scylla-monitoring-scylla-monitoring-4.y/

Replace “y” with the new minor and patch release number, for example, 4.0.0.zip

Setting the server's files
--------------------------

Copy the ``scylla_servers.yml`` and ``scylla_manager_servers.yml`` from the version that is already installed.

.. code-block:: bash

                cp /path/to/monitoring/3.x/prometheus/scylla_servers.yml prometheus/
                cp /path/to/monitoring/3.x/prometheus/scylla_manager_servers.yml.yml prometheus/

Validate the new version is running the correct version
-------------------------------------------------------

run:

.. code-block:: bash

                ./start-all.sh --version

To validate the Scylla-Monitoring version.

Running in test mode
====================

This section is optional. It shows you how to run two monitoring stacks side by side. You can skip this section entirely and move to
switching to the new version section.


Running second monitoring stack
--------------------------------

We need to use different ports to run two monitoring stacks in parallel (i.e., the older 3.x version and the new 4.x stack).

.. code-block:: bash

                ./start-all.sh -p 9091 -g 3001 -m 9095

Browse to ``http://{ip}:9091`` and check the Grafana dashboard

Note that we are using different port numbers for Grafana, Prometheus, and the Alertmanager.

.. caution::

   Important: do not use the local dir flag when testing!

When you are satisfied with the data in the dashboard, you can shut down the containers.

.. caution::

   Important: Do not kill the 3.x version that is currently running!

Killing the new 4.y Monitoring stack in testing mode
----------------------------------------------------

Use the following command to kill the containers:

.. code-block:: bash

                ./kill-all.sh -p 9091 -g 3001 -m 9095

You can start and stop the new 3.y version while testing.

Migrating
=========

Move to version 4.y (the new version)
-------------------------------------

Note: migrating will cause a few seconds of blackout in the system.

We assume that you are using external volume to store the metrics data.


Backup
^^^^^^

We suggest to copy the Prometheus external directory first and use the copy as the data directory for the new monitoring stack.
Newer Monitoring stack uses newer Promethues versions, and keeping a backup of the prometheus dir would allow you to rollback.

Kill all containers
^^^^^^^^^^^^^^^^^^^

At this point you have two monitoring stacks installed with the older version running.

If you run the new version in testing mode kill it by following the instructions on how to `Killing the new 4.y Monitoring stack in testing mode`_
in the previous section.

kill the older 3.x version containers by running:

.. code-block:: bash

                ./kill-all.sh

Start version 4.y in normal mode


From the new root of the `scylla-monitoring-scylla-monitoring-4.y` run

.. code-block:: bash

                ./start-all.sh -d /path/to/copy/data/dir


Point your browser to ``http://{ip}:3000`` and see that the data is there.

Rollback to version 3.x
-----------------------


To rollback during the testing mode, follow `Killing the new 4.y Monitoring stack in testing mode`_ as explained previously
and the system will continue to operate normally.

To rollback to version 3.x after you completed moving to version 4.y (as shown above).
run:

.. code-block:: bash

                ./kill-all.sh
                cd /path/to/scylla-grafana-3.x/
                ./start-all.sh -d /path/to/original/data/dir

Related Links
=============

* `Scylla Monitoring </operating-scylla/monitoring/>`_
* :doc:`Upgrade</upgrade/index>`
