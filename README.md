
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

### Run

```
./start-all.sh
```

### Load original data to prometheus server

```
Additional parameters:
  -v <data>:/prometheus

Full commandline:
  sudo docker run -d -v <data>:/prometheus -v $PWD/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:Z -p 9090:9090 --name aprom prom/prometheus:v1.0.0

Comment:
  <data> is the local path to original data directory

Data source:
1. Download from docker prometheus server, reference:
https://github.com/scylladb/scylla/wiki/How-to-report-a-Scylla-problem#prometheus
2. Get from Scylla-Cluster-Test log.
3. etc
```

### Kill

```
./kill-all.sh
```

### Use
Direct your browser to `your-server-ip:3000`

### Update Scylla servers to send metrics
See [here](https://github.com/scylladb/scylla/wiki/Monitor-Scylla-with-Prometheus-and-Grafana#setting-scylla)
