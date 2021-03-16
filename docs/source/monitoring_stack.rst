===============================
Install Scylla Monitoring Stack
===============================

.. contents::
   :depth: 2
   :local:

This document describes the setup of Scylla Monitoring Stack, based on `Scylla Prometheus API`_.

The Scylla Monitoring Stack needs to be installed on a dedicated server, external to the Scylla cluster. Make sure the Scylla Monitoring Stack server has access to the Scylla nodes so that it can pull the metrics over the Prometheus API.

For evaluation, you can run Scylla Monitoring Stack on any server (or laptop) that can handle three Docker instances at the same time. For production, see recommendations below.

.. include:: min-prod-hw.rst

.. _`Scylla Prometheus API`: monitoring_apis#prometheus

Prerequisites
-------------

* Follow the Installation Guide and install `docker`_ on the Scylla Monitoring Stack Server. This server can be the same server that is running Scylla Manager. Alternatively, you can `Deploy Scylla Monitoring Stack Without Docker <monitor_without_docker>`_ .

.. _`docker`: https://docs.docker.com/install/

Docker Post Installation
------------------------

Docker post installation guide can be found `here`_

.. _`here`: https://docs.docker.com/install/linux/linux-postinstall/

.. note::

   Avoid running the container as root.

To avoid running docker as root, you should add the user you are going to use for Scylla Monitoring Stack to the Docker group.

1. Create the Docker group.

.. code-block:: sh

   sudo groupadd docker

2. Add your user to the docker group. Log out and log in again. The new group will be active for this user on next login.

.. code-block:: sh

   sudo usermod -aG docker $USER

3. Start Docker by calling:

.. code-block:: sh

   sudo systemctl enable docker

Install Scylla Monitoring Stack
-------------------------------

**Procedure**

1. Download and extract the latest `Scylla Monitoring Stack binary`_;.

.. _`Scylla Monitoring Stack binary`: https://github.com/scylladb/scylla-monitoring/releases

.. code-block:: sh
   :substitutions:

   wget https://github.com/scylladb/scylla-monitoring/archive/scylla-monitoring-|version|.tar.gz
   tar -xvf scylla-monitoring-|version|.tar.gz
   cd scylla-monitoring-scylla-monitoring-|version|

As an alternative, you can clone and use the Git repository directly.

.. code-block:: sh

   git clone https://github.com/scylladb/scylla-monitoring.git
   cd scylla-monitoring
   git checkout branch-3.6

2. Start Docker service if needed

.. code-block:: sh

   sudo systemctl restart docker

Configure Scylla Monitoring Stack
---------------------------------

To monitor the cluster, Scylla Monitoring Stack (Specifically the Prometheus Server) needs to know the IP of all the nodes and the IP of the Scylla Manager Server (if you are using Scylla Manager).

This configuration can be done from files, or using the Consul_ api.

.. _Consul: https://www.consul.io/


Scylla Manager 2.0 and higher supports the Consul API.

Configure Scylla nodes from files
.................................


1. Create ``prometheus/scylla_servers.yml`` with the targets' IPs (the servers you wish to monitor).

.. note::
   It is important that the name listed in ``dc`` in the ``labels`` matches the datacenter names used by Scylla.
   Use the ``nodetool status`` command to validate the datacenter names used by Scylla.

For example:

.. code-block:: yaml

   - targets:
         - 172.17.0.2
         - 172.17.0.3
     labels:
         cluster: cluster1
         dc: dc1

.. note:: If you want to add your managed cluster to Scylla Monitoring Stack, add the IPs of the nodes as well as the cluster name you used when you `added the cluster`_ to Scylla Manager. It is important that the label ``cluster name`` and the cluster name in Scylla Manager match.

..  _`added the cluster`: https://scylladb.github.io/scylla-manager/2.2/add-a-cluster.html

*Using IPV6*

To use IPv6 inside scylla_server.yml, add the IPv6 addresses with their square brackets and the port numbers.

For example:

.. code-block:: yaml

   - targets:
         - "[2600:1f18:26b1:3a00:fac8:118e:9199:67b9]:9180"
         - "[2600:1f18:26b1:3a00:fac8:118e:9199:67ba]:9180"
     labels:
         cluster: cluster1
         dc: dc1

.. note:: For IPv6 to work, both scylla Prometheus address and node_exporter's `--web.listen-address` should be set to listen to an IPv6 address.


For general node information (disk, network, etc.) Scylla Monitoring Stack uses the ``node_exporter`` agent that runs on the same machine as Scylla does.
By default, Prometheus will assume you have a ``node_exporter`` running on each machine. If this is not the case, for example if Scylla runs in a container and the node_exporter runs on the host, you can override the ``node_exporter``
targets configuration file by creating an additional file and passing it with the ``-n`` flag.

.. note::
   By default, there is no need to create ``node_exporter_server.yml``. Prometheus will use the same targets it uses for
   Scylla and will assume you have a ``node_exporter`` running on each Scylla server.


If needed, you can set your own target file instead of the default ``prometheus/scylla_servers.yml``, using the ``-s`` for Scylla target files.

For example:

.. code-block:: yaml

   ./start-all.sh -s my_scylla_server.yml -d prometheus_data


Mark the different Data Centers with Labels.

As can be seen in the examples, each target has its own set of labels to mark the cluster name and the data center (dc).
You can add multiple targets in the same file for multiple clusters or multiple data centers.

You can use the ``genconfig.py`` script to generate the server file. For example:

.. code-block:: yaml

   ./genconfig.py -d myconf -dc dc1:192.168.0.1,192.168.0.2 -dc dc2:192.168.0.3,192.168.0.4

This will generate a server file for four servers in two datacenters server ``192.168.0.1`` and ``192.168.0.2`` in dc1 and ``192.168.0.3`` and ``192.168.0.4`` in dc2.

OR

The ``genconfig.py`` script can also use ``nodetool status`` to generate the server file using the ``-NS`` flag.

.. code-block:: yaml

   nodetool status | ./genconfig.py -NS


2. Connect to `Scylla Manager`_ by creating ``prometheus/scylla_manager_servers.yml``
If you are using Scylla Manager, you should set its IP and port in this file.

You must add a scylla_manager_servers.yml file even if you are not using the manager.
You can look at: ``prometheus/scylla_manager_servers.example.yml`` for an example.

..  _`Scylla Manager`: https://scylladb.github.io/scylla-manager/

For example if `Scylla Manager` host IP is `172.17.0.7` ``prometheus/scylla_manager_servers.yml`` would look like:

.. code-block:: yaml

   # List Scylla Manager end points

   - targets:
     - 172.17.0.7:5090

Note that you do not need to add labels to the Scylla Manager targets.

Configure Scylla nodes using Scylla-Manager Consul API
......................................................

Scylla Manager 2.0 has a Consul_ like API.

.. _Consul: https://www.consul.io/


When using the manager as the configuration source, there is no need  to set any of the files.
Instead you should set the scylla-manager IP from the command line using the `-L` flag.

For example:

.. code-block:: yaml

   ./start-all.sh -L 10.10.0.1


.. note::
   If you are running Scylla-Manager on the same host as Scylla-Monitoring you should use -l flag so that the localhost address
   will be available from within the container.

Connecting Scylla-Monitoring to Scylla
......................................

Scylla-Manager version 3.5 and higher can read tables from a Scylla node using CQL. If your Scylla cluster is user/password protected (See `Scylla  Authorization`_) you should assign a user and password for the Scylla-Grafana connection.

.. _`Scylla  Authorization`: https://docs.scylladb.com/operating-scylla/security/enable-authorization/


You can limit the user to read only, currently it only read table from the system keyspace.

To set a user/password edit `grafana/provisioning/datasources/datasource.yaml`.

Under **scylla-datasource** Uncomment the **secureJsonData** part and set the user and password.

Use an external directory for the Prometheus data directory
...........................................................

The ``-d`` flag, places the Prometheus data directory outside of its container and by doing that makes it persistent.

.. note:: Specifying an external directory is important for systems in production. Without it, 
          every restart of the monitoring stack will result in metrics lost. 

If the directory provided does not exist, the ``start-all.sh`` script will create it. Note that you should avoid running docker as root, the ``start-all.sh`` script
will use the user permissions that runs it. This is important if you want to place the prometheus directory not under the user path but somewhere else, for example ``/prometheus-data``.

In that case, you need to create the directory before calling ``start-all.sh`` and make sure it has the right permissions for the user running the command.

Add Additional Prometheus Targets
....................................
There are situations where you would like to monitor additional targets using the Prometheus server of the monitoring stack.
For example, an agent that runs on a firewall server.
The Prometheus server reads its targets from a file, this file is generated from a template when calling ``start-all.sh``.
To add your targets you would need to edit the template file before calling ``start-all.sh``.

The template file is either ``prometheus/prometheus.yml.template`` if Prometheus reads the Scylla target from file, or ``prometheus/prometheus.consul.yml.template``
if Prometheus gets Scylla targets from the manager Consul API.

You can add a target at the end of the file, for example, the following example would read from a server with IP address 17.0.0.1 with a Prometheus port of 7000.


.. code-block:: yaml

    - job_name: 'myservice'
      # Override the global default and scrape targets from this job every 5 seconds.
      scrape_interval: 5s
      static_configs:
        - targets:
          - 17.0.0.1:7000




Start and Stop Scylla Monitoring Stack
--------------------------------------

Start
.....

.. code-block:: yaml

   ./start-all.sh -d prometheus_data


Stop
....

.. code-block:: yaml

   ./kill-all.sh


Start a Specific Scylla Monitoring Stack Version
.................................................

By default, start-all.sh will start with dashboards for the latest Scylla Open source version and the latest Scylla Manager version.

You can specify specific scylla version with the ``-v`` flag and Scylla Manager version with ``-M`` flag.

Multiple versions are supported. For example:

.. code-block:: sh

   ./start-all.sh -v 2020.1,2019.1 -M 2.1 -d prometheus-data

will load the dashboards for Scylla Enterprise versions ``2020.1`` and ``2019.1`` and the dashboard for Scylla Manager ``2.1``


Accessing the `localhost`
.........................

The Prometheus server runs inside a Docker container if it needs to reach a target on the local- host: either Scylla or Scylla-Manager, it needs to use the host network and not the Docker network.
To do that run ./start-all.sh with the -l flag. For example:

.. code-block:: sh

   ./start-all.sh -l -d prometheus-data

Configure rsyslog on each Scylla node
.....................................
generates metrics and alerts from logs. To get full functionality, you should use rsyslog_. Scylla Monitoring Stack will act as an additional rsyslog server.
Scylla Monitoring Stack collects Scylla logs using Loki and generates metrics and alerts based on these logs. 
To use this feature, you need to direct logs from each Scylla node to Loki.
The recommended method to do this is by using rsyslog_, where Scylla Monitoring Stack (Loki) acts as an additional rsyslog server.
.. note:: Scylla can send logs to more than one log collection service.

.. _rsyslog: https://www.rsyslog.com/



**Prerequisite**, make sure rsyslog is installed and running. If rsyslog is not installed, follow the installation instruction_.

.. _instruction: https://www.rsyslog.com/doc/v8-stable/installation/index.html

Add scylla's rsyslog configuration file. Add the file: ``/etc/rsyslog.d/scylla.conf``.

If Scylla Monitoring Stack IP is 10.0.0.1, the file should look like

.. code-block:: sh

   if $programname ==  'scylla' then @@10.0.0.1:1514;RSYSLOG_SyslogProtocol23Format

Restart rsyslog for the configuration to take effect.

.. code-block:: sh


   systemctl restart rsyslog

View Grafana Dashboards
-----------------------

Point your browser to ``your-server-ip:3000``
By default, Grafana authentication is disabled. To enable it and set a password for user admin use the ``-a`` option.
