# Scylla monitoring with Grafana and Prometheus

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
For example

```
  - targets: ["172.17.0.3:9103","172.17.0.2:9103"]
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
