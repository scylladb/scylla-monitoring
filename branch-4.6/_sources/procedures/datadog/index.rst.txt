=====================================
Scylla Monitoring Datadog Integration
=====================================

The safest way to use Datadog with Scylla is to load the metrics, using a  Datadog Agent, from a Prometheus server and not directly from  Scylla nodes.
The integration consists of:

1. Installing and configuring the Datadog Agent.
2. Add Datadog recording rules.
3. Loading Scylla dashboard to Datadog.
4. Optionally load Monitor (Alerts).

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
Other Scylla users, download the configuration file :download:`conf.yaml <conf.yaml>` and replace the ip address of the Prometheus server.


Post configuration
^^^^^^^^^^^^^^^^^^
Restart the agent based on your installation. Scylla metrics should be visible in Datadog.


.. note::  By default, Datadog will not scrap per-shard metrics. To enable per-shard metrics, edit the conf.yaml file and replace dd=~"1" with dd=~"1|2"

Add datadog recording rules
===========================
Non Scylla Cloud users, download the rules configuration file :download:`datadog.rules.yml <datadog.rules.yml>` if you need per-shard metrics, download :download:`datadog.rules-with-shards.yml <datadog.rules-with-shards.yml>` and place it under prometheus/prom_rules/.
Per-shards metrics adds load and cost to both the Prometheus server and Datadog agent and server, so only use it if needed.

Cloud users, skip this step, it's been take care for by the cloud.

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
