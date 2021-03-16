The start-all.sh command
========================

Scylla Monitoring Stack is container-based, the simplest way to configure and start the monitoring is with the `start-all.sh` command.

The `start-all.sh` script is a small utility that sets the dashboards and starts the containers with the appropriate configuration.

General Options
---------------

**-h** Help, Print the help, and exit.

**--version** print the current Scylla-Monitoring stack version, and exit.

**-l** local. Use the host network. This is important when one of the containers need access to an application that runs on the host.
For example, when Scylla Manager runs on the localhost next to the monitoring.
Because the monitoring applications run inside containers by default their local IP address (127.0.0.1) is the container local IP address.
You cannot use port mapping when using the ``-l`` flag

**-A bind-to-ip-address** Bind the listening-address to an explicit IP address.

**-D encapsulate docker param** Allows passing additional parameters to all the docker containers.

**--auto-restart** When set, Docker will automatically restart all the services inside the containers in case of a failure.

Grafana Related Commands
------------------------

**-G path/to/grafana data-dir** Use an external directory for the Grafana database. 
This flag places the Grafana data directory outside of its container and by doing that makes it persistent. 
This is only important if you are creating your own dashboards using the grafana GUI and wish to keep them. 
If not used, each run of the containers will clear all of Grafana information.

**-v comma-separated versions** Each Scylla version comes with its own set of dashboards. By default, Grafana starts with the two latest versions. The ``-v`` flag allows specifying a specific version or versions.

**-M scylla-manager version** Each Scylla-Manager version has its own dashboard. By default, Grafana starts with the latest Scylla Manager version.  The ``-M`` flag allows specifying a specific version.

**-j dashboard** Allows adding dashboards to Grafana, multiple parameters are supported.

**-c grafana environment variable** Use this parameter to override Grafana's configuration settings.  The ``-c`` flag allows adding an environment variable to Grafana and by doing so alters its configuration.

**-g grafana port** Override the default grafana port, this is done using port mapping, note that port mapping does not work when using the host network.

**-a admin password** Allows specifying the admin password.

**-Q Grafana anonymous role** By default, anonymous users have admin privileges. That means they can create and edit dashboards. The ``-Q`` flag changes this behavior  by setting the role privileges to one of Admin, Editor, or Viewer.

Grafana LDAP support
^^^^^^^^^^^^^^^^^^^^
Grafana supports LDAP_ for authentication and authorization.

.. _LDAP: https://grafana.com/docs/grafana/latest/auth/ldap/

Use the ``-P`` flag to supply an LDAP configuration file.

**-P ldap-config-file**

Prometheus Related Commands
---------------------------

**-d path/to/data-dir** Use an external directory for the Prometheus data directory.
This flag places the Prometheus data directory outside of its container and by doing that makes it persistent.

.. note:: Specifying an external directory is important for systems in production. Without it, 
          every restart of the monitoring stack will result in metrics lost.

**-p prometheus-port** Override the default Prometheus port, this is done using port mapping, note that port mapping does not work when using the host network.

**-b command-line options** Allows adding command-line options that will be passed to the Prometheus server.

**-s scylla-target-file** Specify the location of the Scylla target files. This file contains the IP addresses of the Scylla nodes.

**-n node-target-file** Scylla Monitoring Stack collects OS metrics (Disk, network, etc.) using an agent called node_exporter. By default, Scylla Monitoring Stack assumes that there is a node_exporter running beside each Scylla node, for situations that this is not the case, for example, Scylla runs inside a container and the relevant metrics are of the host machine, it is possible to specify a target file for the node_exporter agents. 

**-N manager target file** Specify the location of the Scylla Manager target file.

**-R prometheus-alert-file** By default Prometheus alert rules are found in ``prometheus.rules.yml`` in the ``prometheus`` directory. The ``-R`` flag allows specifying a different location.

**-L manager-address** Using Scylla Manager **Consul** API to resolve the servers' IP address. When using this option, Prometheus will ignore the target files even if they are explicitly passed in the command line.

Prometheus Retention Period
^^^^^^^^^^^^^^^^^^^^^^^^^^^
Prometheus retention period is set for 2 weeks by default. A common request is how to set it to something else.
It is also an opportunity to demonstrates how to set a Prometheus specific command line option.
Prometheus storage configuration is covered here_.

.. _here: https://prometheus.io/docs/prometheus/latest/storage/#operational-aspects

For example to set the retention time to 30 days add ``-b "-storage.tsdb.retention.time=30d"`` to the ``start-all.sh`` command

Alert Manager 
-------------

alertmanager handles the alerts and takes the following parameters:

**-m alertmanager-port** Override the default Alertmanager port, this is done using port mapping, note that port mapping does not work when using the host network.

**-r alert-manager-config** By default, the Alertmanager takes its configuration from ``rule_config.yml`` in the ``prometheus`` directory. The ``-r`` flag overrides it to another file.prometheus

**-C alertmanager-commands** Allows adding an arbitrary command line to the alertmanager container starting command.
