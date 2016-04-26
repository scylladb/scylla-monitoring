
The monitoring infrastructure consists of several components, wrapped in docker containers:
 * `prometheus` - collects and stores metrics
 * `grafana` - dashboard server

### prerequisites
* git
* docker

### Install

```
git clone https://github.com/tzach/scylla-grafana-monitoring.git
cd scylla-grafana-monitoring
```

Update `prometheus/prometheus.yml` with the targets (server you wish to monitor). 

### Run locally

```
./start-all-local.sh
```

### Run on EC2

```
./start-all-ec2.sh
```

### Use
Direct your browser to `your-server-ip:3000`

### Update Scylla servers to send metrics
See [here](https://github.com/scylladb/scylla/wiki/Monitor-Scylla-with-Prometheus-and-Grafana#setting-scylla)
