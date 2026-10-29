=====================================
Scylla Monitoring Datadog Integration
=====================================

The safest way to use Datadog with Scylla is to load the metrics, using a  Datadog Agent, from a Prometheus server and not directly from  Scylla nodes.
The integration consists of:

1. Installing and configuring the Datadog Agent.
2. Loading Scylla dashboard to Datadog.
3. Optionally load Monitor (Alerts).

.. note::  Scylla Cloud users, use and update the proper configuration file.

Install And configure the Datadog Agent
=======================================

Start by following `Installation <https://docs.datadoghq.com/agent/>`_ guide. The datadog agent should run on a machine that can reach the Prometheus server.

Once the Datadog agent is working, download the configuration file and place it under /etc/datadog-agent/conf.d/prometheus.d/conf.yaml

Scylla Cloud Users
^^^^^^^^^^^^^^^^^^
Scylla Cloud users, download the configuration file :download:`conf.yaml <cloud-conf.yaml>` move it to: /etc/datadog-agent/conf.d/prometheus.d/conf.yaml


Edit the file. You must replace the cluster id (CLUSTER_ID) and the token (TOKEN).

Other Scylla Users
^^^^^^^^^^^^^^^^^^
Other Scylla users, download the configuration file :download:`conf.yaml <conf.yaml>` and replace the ip address of the promemtheus server.


Post configuration
^^^^^^^^^^^^^^^^^^
Restart the agent based on your installation. Scylla metrics should be visible in Datadog.


Upload the Dashboard
====================
Download the dashboard file :download:`dashboard.json <dashboard.json>`.
Create a new dashboard in Datadog and import the json file you downloaded. 

Using the Dashboard
===================
We created a Datadog dashboard that resembles the Grafana dashboards available to Scylla and Scylla-Cloud users.

.. image:: datadog.png

The dashboard contains some specific filtering and perspectives:
First, you can choose between shard, instance, dc, or cluster view.
This will aggregate the metrics in the graphs accordingly.
Second, you can filter to see specific shards, nodes, or DCs.

.. note::  Pay attention that some of the combinations are conflicting. For example, you cannot filter by DC when looking at a cluster view. If no data displayed, remove the filters first.

Adding Monitor
==============
Alerts in Datadog called Monitor. Download the monitor file :download:`monitor.json <monitor.json>`. Go to the Monitor section in datadog and import the json.
