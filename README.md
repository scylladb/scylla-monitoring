# Scylla monitoring with Grafana and Prometheus
___
*** Notice to users using git ***

The monitoring stack was changed to use versions and releases.

Users should move to a stable release. Current release is 1.0, if you are using master
do `git checkout origin/branch-1.0` to switch to 1.0 version and make sure that you are using the latest stable version.
___

### Introduction

An out-of-the-box configuration will have a server dedicated to running both Prometheus and Grafana. Some teams may already have existing Promotheus and/or Grafana infrastructure, in which case you are able to use your existing architecture.

The monitoring infrastructure consists of several components, wrapped in Docker containers:
 * `prometheus` - collects and stores metrics
 * `grafana` - dashboard server
 * `alertmanager` - The alert manager collect Prometheus alerts

### Prerequisites

* docker
* python module pyyaml (for `genconfig.py`)
* python module json (for `make_dashboards`)

#### CentOS: Prerequisites Installation

On CentOS, you can do:

```bash
sudo yum install -y git docker python-pip
sudo pip install --upgrade pip
sudo pip install pyyaml
```

#### Ubuntu 16.04: Prerequisites Installation

On Ubuntu 16.04, you can do:

You'll need to add the Docker repo to your `/etc/apt/sources.list` (and accept the key, see Docker website for full instructions).

```bash
deb [arch=amd64] https://download.docker.com/linux/ubuntu xenial stable
```

On Ubuntu, the latest package name is `docker-ce` for "Community Edition". You may want/need to adjust other Docker specific settings to meet your requirements. These instructions will get you a basic working Docker host.

```bash
sudo apt-get update && apt-get install -y python-pip docker-ce git
sudo pip install --upgrade pip
sudo pip install pyyaml
```

### Install
#### Installing archived project

Download the latest version from:
https://github.com/scylladb/scylla-grafana-monitoring/releases



#### Installing source from git

```
git clone https://github.com/scylladb/scylla-grafana-monitoring.git
cd scylla-grafana-monitoring
```

Start docker service if needed
```
ubuntu $ sudo systemctl restart docker
centos $ sudo service docker start
```

### Configuration
In standard installations of Scylla, each node in the cluster provides two sources of metrics: Scylla itself (on port 9180), and a "node exporter" process which provides (on port 9100) standard hardware and OS metrics. We need to tell Prometheus the list of nodes which provides each of these two sources of metrics.

By default, the `start-all.sh` script (which we will use to run Prometheus and Grafana) gets the configuration of these two sources from the files `prometheus/scylla_servers.yml` and `prometheus/node_exporter_servers.yml`. These files should be edited to list the Scylla nodes, a.k.a. *targets*.

For example, if you have two nodes (172.17.0.2 and 172.17.0.3) in a single dc cluster, update `prometheus/scylla_servers.yml` to say they provide Scylla metrics on port 9180:

```
- targets:
      - 172.17.0.2:9180
      - 172.17.0.3:9180
  labels:
       cluster: cluster1
       dc: dc1
```

similarly, update `prometheus/node_exporter_servers.yml` to list the same nodes as additionally providing "node exporter" OS-level metrics on port 9100:

```
- targets:
      - 172.17.0.2:9100
      - 172.17.0.3:9100
  labels:
       cluster: cluster1
       dc: dc1
```
#### Clusters and Data centers
Note that each "targets" section (there could be more than one) come with its own cluster and dc labels.
For multiple DC or multiple cluster create multiple "targets" entries, each with the right cluster or dc.

#### Using your own target files
You can also use your own target files instead of updating `scylla_servers.yml` and `node_exporter_servers.yml`, using the `-s` for scylla target file and `-n` for node taget file. For example:

```
./start-all.sh -s my_scylla_servers.yml -n my_node_exporter_servers.yml -d data_dir
```

In many deployments the contents of those files are very similar, with the same servers being listed differing only in the ports scylla and node_exporter listen to. To automatically generate the target files, one can use the `genconfig.py` script, using the `-n` and `-s` flags to control which files get created:

```
./genconfig.py -ns -d myconf 192.168.0.1 192.168.0.2
```

After that, the monitoring stack can be started pointing to the servers at `192.168.0.1` and `192.168.0.2` with::

```
./start-all.sh -s myconf/scylla_servers.yml -n myconf/node_exporter_servers.yml
```

#### node_exporter Installation
[node_exporter](https://github.com/prometheus/node_exporter) is an exporter of hardware and OS metrics such as disk space.

For a fully functional dashboard you need to have the node_exporter running on each of the nodes and configure the prometheus accordingly.

As part of Scylla installation, the `scylla_setup` script will prompt to install node_exporter. If you skipped that step, you could always install node_exporter later with the  `node_exporter_install` script.


`node_exporter_install` will download and install the node_exporter as a service.


### Run

```
./start-all.sh -d data_dir
```

For full list of options
```
./start-all.sh -h
```

#### Multiple versions support
As counters change their names between versions, we create a new dashboard for each new version.
We use tags to distinguish between the different versions, to keep the dashboard menu, relatively short,
by default, only the last two releases are loaded. You can load specific versions by using the `-v` flag.
 
* You can supply multiple comma delimited versions, for example to load only 1.5 and 1.6 version:
 ```
 ./start-all.sh -v 1.5,1.6
 ```

* Use the `all` to load all available versions.

* The master branch is called master, so to load 1.6 and master you would use:
 ```
 ./start-all.sh -v 1.6,master
 ```

* If you only need the latest version you can use:
 ```
 ./start-all.sh -v latest
 ```
___
**Note: The -d data_dir is optional, but without it, Prometheus will erase all data between runs.**


**For systems in production it is recommended to use an external directory.**
___

#### Prometheus Command Line Options

```
-b storage.local.retention=1000h -b query.staleness-delta=1m
```

#### connecting Scylla and the Monitoring locally - the local flag
When running the Prometheus and Grafana on the same host as scylla, use the local `-l` flag, so processes inside the
containers will share the host network stack and would have access to the `localhost`.

### Kill

```
./kill-all.sh
```

### Use
Direct your browser to `your-server-ip:3000`
By default, Grafana authentication is disabled. To enable it and set a password for user admin use the `-a` option

#### Choose Disk and network interface
The dashboard holds a drop down menu at its upper left corner for disk and network interface.
You should choose relevant disk and interface for the dashboard to show the graphs. 

### Update Scylla servers to send metrics
See [here](https://github.com/scylladb/scylla/wiki/Monitor-Scylla-with-Prometheus-and-Grafana#14-and-later-instruction)

### Load original data to Prometheus server

Additional parameters:
  -d data_dir

Full commandline:

```
./start-all.sh -d data_dir
```
Comment:
  `data_dir` is the local path to original data directory

Data source for Prometheus data:
* Download from Docker Prometheus server, reference: https://github.com/scylladb/scylla/wiki/How-to-report-a-Scylla-problem#prometheus
* Get from Scylla-Cluster-Test log.
* Others

### Using your own Grafana installation

Some users who already have grafana installed can just upload the Scylla dashboards into your existing grafana environment.
This is possible using the `load-grafana.sh` script.

For example, if you have prometheus running at `192.168.0.1:9090`, and grafana at localhost's port `3000`, you can do:

```
./load-grafana.sh -p 192.168.0.1:9090 -g 3000
```

### Alertmanager
Prometheus [Alertmanager](https://prometheus.io/docs/alerting/alertmanager/) handles alerts that are generated by the Prometheus server.

Alerts are generated according to the [Alerting rules](https://prometheus.io/docs/prometheus/1.8/configuration/alerting_rules/).

The Alertmanager listen on port `9093` and you can use a web-browser to connect to it.
