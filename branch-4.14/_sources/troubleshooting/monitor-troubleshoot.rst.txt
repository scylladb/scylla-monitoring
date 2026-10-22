Troubleshoot Scylla Monitoring Stack
====================================


This document describes steps that need to be done to troubleshoot monitoring problems when using `Grafana/Prometheus`_ monitoring tool.

..  _`Grafana/Prometheus`: ../monitoring-apis

Problem
~~~~~~~

Scylla-Manager 2.2 with Duplicate information
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Scylla Manager 2.2 change the default metrics (Prometheus) reporting ports:

* For Manager server: from 56090 to 5090
* For Manager Agent: from 56090 to 5090

For backward compatibility, Scylla Monitoring Stack 3.5 default configuration reads from **both** Manager ports, old and new, so you do not have to update the Prometheus configuration when upgrading to Manager 2.2



However, if you configure ``scylla_manager_server.yml`` file with the new port, Scylla-Manager dashboard will report all metrics twice.

The easiest way around this is to edit ``prometheus/prometheus.yml.template`` and remove the ``scylla_manager1`` job.

Note that for this change to take effect you need to run ``kill-all.sh`` followed by ``start-all.sh``.

A Container Fails To Start
^^^^^^^^^^^^^^^^^^^^^^^^^^^

When running ``./start-all.sh`` a container can fail to start. For example you can see the following error message:

.. code-block:: shell

   Wait for Prometheus container to start........Error: Prometheus container failed to start


Should this happen, check the Docker logs for more information.

.. code-block:: shell

   docker logs aprom

Usually the reason for the failure is described in the logs.

Files And Directory Permissions
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


.. note::

   Avoid running Docker containers as root.

The preferred way of running the container is using a non root user.
See the `monitoring`_ Docker post-installation section.

.. _`monitoring`: ../monitoring-stack#docker-post-installation


If a container failed to start because of a permission problem, make sure
the external directory you are using is owned by the current user and that the current user has the proper permissions.

.. note::

   If you started the container in the past as root, you may need to change the directory and files ownership and permissions.

For example if your Prometheus data directory is ``/prom-data`` and you are using ``centos`` user

.. code-block:: shell

   ls -la /|grep prom-data

   drwxr-xr-x    2 root root  4096 Jun 25 17:51 prom-data

   sudo chown -R centos:centos /prom-data

   ls -la /|grep prom-data

   drwxr-xr-x    2 centos centos  4096 Jun 25 17:51 prom-data



No Data Points
^^^^^^^^^^^^^^

``No data points`` on all data charts.

Solution
........

If there are no data points, or if a node appears to be unreachable when you know it is up, the immediate suspect is the Prometheus connectivity.

1. Login to the Prometheus console:

2. Point your browser to ``http://{ip}:9090``, where {ip} is the Prometheus IP address.

3. Go to the target tabs: ``http://{ip}:9090/targets`` and see if any of the targets are down and if there are any error messages.

  * Make sure you are not using the local network for local IP range When using Docker containers, by default, the local IP range (127.0.0.X) is inside the Docker container and not the host local address. If you are trying to connect to a target via the local IP range from inside a Docker container, you need to use the ``-l`` flag to enable local network stack.

  * Confirm Prometheus is pointing to the wrong target. Check your ``prometheus/scylla_servers.yml``. Make sure Prometheus is pulling data from the Scylla server.

  * Your dashboard and Scylla version may not be aligned. You can specify a specific Scylla version with ``-v`` flag to the start-all.sh script.

For example:

.. code-block:: shell

   ./start-all.sh -v 2024.1

More on start-all.sh `options`_.

..  _`options`: ../monitoring-stack/


Grafana Chart Shows Error (!) Sign
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Run this procedure on the Scylla Monitoring Stack server.

If the Grafana charts show an error (!) sign, there is a problem with the connection between Grafana and Prometheus.

Solution
.........

On the Scylla Monitoring Stack server:

1. Check Prometheus is running using ``docker ps``.

* If it is not running check the ``prometheus.yml`` for errors.

For example:

.. code-block:: shell

   CONTAINER ID  IMAGE    COMMAND                  CREATED         STATUS         PORTS                                                    NAMES
   41bd3db26240  monitor  "/docker-entrypoin..."   25 seconds ago  Up 23 seconds  7000-7001/tcp, 9042/tcp, 9160/tcp, 9180/tcp, 10000/tcp   monitor

* If it is running, go to "Data Source" in the Grafana GUI, choose Prometheus and click Test Connection.

Grafana Shows Server Level Metrics, but not Scylla Metrics
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Grafana shows server level metrics like disk usage, but not Scylla metrics.
Prometheus fails to fetch metrics from Scylla servers.

Solution
.........

* Use ``curl <scylla_node>:9180/metrics`` to fetch metric data from Scylla.  If curl does not return data, the problem is the connectivity between the Scylla Monitoring Stack and Scylla server. In that case, check your IPs and firewalls.

For example

.. code-block:: shell

   curl 172.17.0.2:9180/metrics

Grafana Shows Scylla Metrics, but not Server Level Metrics
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Grafana dashboards show Scylla metrics, such as load, but not server metrics such as disk usage.
Prometheus fails to fetch metrics from ``node_exporter``.

Solution
.........

1. Make sure that ``node_exporter`` is running on each Scylla server (by login to the machine and running ``ps -ef | grep node_exporter``). ``node_exporter`` is installed with ``scylla_setup``.
to check that ``node_exporter`` is installed, run ``node_exporter --version``, If it is not, make sure to install and run it.

2. If it is running, use ``curl http://<scylla_node>:9100/metrics`` (where <scylla_node> is a Scylla server IP) to fetch metric data from the ``node_exporter``.  If curl does not return data, the problem is the connectivity between Scylla Monitoring Stack and Scylla server. Please check your IPs and firewalls.

Latencies Graphs Are empty
^^^^^^^^^^^^^^^^^^^^^^^^^^
Starting from Scylla Monitoring version 3.8, Scylla Monitoring uses Prometheus' recording rules for performance reasons. Recording rules perform some of the calculations when collecting the metrics, instead of when showing the dashboards.

During a transition period, Scylla Monitoring version 3.x has a fallback mechanism that shows data even if the recording rules are not present.

Scylla Monitoring versions 4.0 and newer rely only on recording rules.

If only the latency graphs are missing, it is because of missing recording rules.

This issue can be avoided in a clean installation, so if you are upgrading, it is recommended to perform a clean installation.

If you are using a standalone Prometheus server, make sure to copy the Prometheus configuration and recording rules as describe in `install without docker`_.

.. _`install without docker`: /install/monitor-without-docker#install-prometheus

Reducing the total number of metrics
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
In ScyllaDB, metrics are reported per shard (core) per node. A cluster with a high number of nodes and cores reports an increased number of metrics which might overload the Monitoring system like Prometheus or Datadog.
Below is one way to reduce the number of metrics reported per ScyllaDB Node.

Remove interrupts from node_exporter
....................................

By default, node_exporter reports interrupt metrics. You can disable interrupts reporting by editing
`/etc/sysconfig/scylla-node-exporter` and remove --collector.interrupts from it.

Working with Wireshark
^^^^^^^^^^^^^^^^^^^^^^^

No metrics shown in the Scylla Monitoring Stack.

1. Install `wireshark`_

..  _`wireshark`: https://www.wireshark.org/#download

2. Capture the traffic between the Scylla Monitoring Stack and Scylla node using the ``tshark`` command.
``tshark -i <network interface name> -f "dst port 9180"``

For example:

.. code-block:: shell

   tshark -i eth0 -f "dst port 9180"

Capture from Scylla node towards Scylla Monitoring Stack server.


In this example, Scylla is running.

.. code-block:: shell

   Monitor ip        Scylla node ip
   199.203.229.89 -> 172.16.12.142 TCP 66 59212 > 9180 [ACK] Seq=317 Ack=78193 Win=158080 Len=0 TSval=79869679 TSecr=3347447210

In this example, Scylla is not running

.. code-block:: shell

   Monitor ip        Scylla node ip
   199.203.229.89 -> 172.16.12.142 TCP 74 60440 > 9180 [SYN] Seq=0 Win=29200 Len=0 MSS=1460 SACK_PERM=1 TSval=79988291 TSecr=0 WS=128
