=============================================
ScyllaDB Cloud Monitoring Datadog Integration
=============================================

For security reasons, the ScyllaDB cloud does not have direct access to the Prometheus server.
To allow external server scrapping, you will need to enable the Prometheus proxy.
The Datadog agent reads from the proxy, which reads from the Promethues server.

1. Installing and configuring the Datadog Agent.
2. Add Datadog recording rules.
3. Loading Scylla dashboard to Datadog.
4. Optionally load Monitor (Alerts).

Scylla Monitoring Datadog Integration Overview
==============================================
A typical ScyllaDB cluster generates thousands of metrics, sometimes even tens of thousands.
The sheer number of metrics is too much for Datadog.

Instead of letting the Datadog agent scrap all metrics, the monitoring stack marks a small subset of metrics with a label and lets the Datadog agent scrap only those.

Install And configure the Datadog Agent
=======================================

Start by following `Installation <https://docs.datadoghq.com/agent/>`_ guide. The datadog agent should run on a machine that can reach the Prometheus Proxy server.

Once the Datadog agent is working, download the configuration file and place it under /etc/datadog-agent/conf.d/prometheus.d/conf.yaml

Download the configuration file :download:`conf.yaml <cloud-conf.yaml>` move it to: /etc/datadog-agent/conf.d/prometheus.d/conf.yaml


Edit the file. You must replace the cluster id (CLUSTER_ID) and the token (TOKEN).

Post configuration
^^^^^^^^^^^^^^^^^^
Restart the agent based on your installation. Scylla metrics should be visible in Datadog.


.. note::  By default, Datadog will not scrap per-shard metrics. To enable per-shard metrics, edit the conf.yaml file and replace dd=~"1" with dd=~"1|2"

Upload the Dashboard
====================
Download the dashboard file :download:`dashboard.json <dashboard.json>`.
Create a new dashboard in Datadog and import the json file you downloaded.

Using the Dashboard
===================
We created a Datadog dashboard that resembles the Grafana dashboards.

.. image:: datadog.png

The dashboard contains some specific filtering and perspectives:
First, you can choose between shard, instance, dc, or cluster view.
This will aggregate the metrics in the graphs accordingly.
Second, you can filter to see specific shards, nodes, or DCs.

.. note::  Pay attention that some of the combinations are conflicting. For example, you cannot filter by DC when looking at a cluster view. If no data displayed, remove the filters first.

Adding Monitor
==============
Alerts in Datadog called Monitor. Download the monitor file :download:`monitor.json <monitor.json>`. Go to the Monitor section in datadog and import the json.
