# ScyllaDB Monitoring Stack

ScyllaDB Monitoring Stack is a full stack for ScyllaDB monitoring and alerting. The stack contains open source tools including Prometheus and Grafana, as well as custom ScyllaDB dashboards and tooling.

![image](monitor.png)

The ScyllaDB Monitoring Stack consists of multiple components, wrapped in Docker containers:

* prometheus - Collects and stores metrics
* grafan-loki - Parses logs and generates metrics and alerts
* alertmanager - Handles alerts
* grafana - Dashboards server

A few optional components are used for additional services

* grafana-image-renderer - Allows you to download a dashboard as an image.
* Thanos sidecar - Allows a centralized Thanos server to read from the local Prometheus server.

## High Level Architecture

![image](monitoring_stack.png)

We use Prometheus for metrics collection and storage, and to generate alerts. Prometheus collects Scylla’s metrics from ScyllaDB and the
host metrics from the node_exporter agent that runs on the ScyllaDB server.

We use Loki for metrics and alerts generation based on logs, Loki gets the logs from rsyslog agents that run on each of the DB servers.

The alertmanager, receives alerts from Prometheus and Loki and distributes them to other systems like email and slack.

We use Grafana to display the dashboards. Grafana gets its data from Prometheus, the alertmanager and directly from ScyllaDB using CQL.

**Choose a topic to get started**:

* [User Guide](https://monitoring.docs.scylladb.com/stable/use-monitoring/index.md)
* [Download and Install](https://monitoring.docs.scylladb.com/stable/install/index.md)
* [Procedures](https://monitoring.docs.scylladb.com/stable/procedures/index.md)
* [Troubleshooting](https://monitoring.docs.scylladb.com/stable/troubleshooting/index.md)
* [Reference](https://monitoring.docs.scylladb.com/stable/reference/index.md)
* [ScyllaDB Monitoring Stack lesson](https://university.scylladb.com/courses/scylla-operations/lessons/scylla-monitoring/) on ScyllaDB University
