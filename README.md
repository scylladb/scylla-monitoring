# Scylla monitoring with Grafana and Prometheus

### Notice for users of Scylla version prior to 1.4
If you are using a Scylla version before 1.4, or if you are using Prometheus over collectd, check out the v0.1 tag.

`git checkout v0.1`

The monitoring infrastructure consists of several components, wrapped in docker containers:
 * `prometheus` - collects and stores metrics
 * `grafana` - dashboard server

### prerequisites
* git
* docker

### Install

```
git clone https://github.com/scylladb/scylla-grafana-monitoring.git
cd scylla-grafana-monitoring
```


Start docker service if needed
```
ubuntu $ sudo systemctl restart docker
centos $ sudo service docker start
```

Update `prometheus/prometheus.yml` with the targets (server you wish to monitor).
For every server there are two targets, one under `scylla` job which is used for the scylla metrics.
Use port 9180.
For example

```
  - targets: ["172.17.0.3:9180","172.17.0.2:9180"]
```
Second, for general node information (disk, network, etc.) add the server under `node_exporter` job. Use port 9100.
For example

```
  - targets: ["172.17.0.3:9100","172.17.0.2:9100"]
```


### Run

```
./start-all.sh
```

### Load original data to prometheus server


Additional parameters:
  -d data_dir

Full commandline:

```
./start-all.sh -d data_dir
```
Comment:
  `data_dir` is the local path to original data directory

Data source for Prometheus data:
* Download from docker prometheus server, reference: https://github.com/scylladb/scylla/wiki/How-to-report-a-Scylla-problem#prometheus
* Get from Scylla-Cluster-Test log.
* Others


### Kill

```
./kill-all.sh
```

### Use
Direct your browser to `your-server-ip:3000`

### Update Scylla servers to send metrics
See [here](https://github.com/scylladb/scylla/wiki/Monitor-Scylla-with-Prometheus-and-Grafana#setting-scylla)
