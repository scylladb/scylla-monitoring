# Scylla monitoring with Grafana and Prometheus

Scylla-Monitoring configuration can be found: http://scylladb.github.io/scylla-monitoring/

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

##### Install Docker

Please follow the instructions at: https://docs.docker.com/install/linux/docker-ce/centos/
Note that Docker was renamed and it is now docker-ce.
If you are running an older docker version, remove it first by following the instruction.

##### Complete Prerequisites Installation

```bash
sudo yum install -y epel-release
sudo yum install -y git python36 python36-PyYAML
```
#### Ubuntu 16.04: Prerequisites Installation

On Ubuntu 16.04, you can do:

##### Install Docker

Please follow the instructions at: https://docs.docker.com/install/linux/docker-ce/ubuntu/ Note that Docker was renamed and it is now docker-ce.
If you are running an older docker version, remove it first by following the instruction.

On Ubuntu, the latest package name is `docker-ce` for "Community Edition". You may want/need to adjust other Docker specific settings to meet your requirements. These instructions will get you a basic working Docker host.

##### Complete Prerequisites Installation

```bash
sudo apt-get update 
sudo apt-get install -y python3 python3-yaml
```

### Docker Post Installation

Docker post-installation guide can be found here: https://docs.docker.com/install/linux/linux-postinstall/

**Note: It is recommended not to run containers as root**

To avoid running docker as root, you should add the user you are going to use to start the monitoring to the docker group.

1. Create the docker group.
```
sudo groupadd docker
```

2. Add your user to the docker group.
```
sudo usermod -aG docker $USER
```

3. Start docker by calling:
```
sudo systemctl enable docker
```


### Install
#### Installing archived project

Download the latest version from:
https://github.com/scylladb/scylla-monitoring/releases



#### Installing source from git

```
git clone https://github.com/scylladb/scylla-monitoring.git
cd scylla-monitoring
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

#### specify node_exporter file
By default, the same configuration (with different ports) will be used for the node_exporter.
You can specify a specific node_exporter target file with the `-n` flag.

A typicall node_exporter configuration file would look like:

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
For multiple DCs or multiple clusters create multiple "targets" entries, each with the right cluster or dc.

#### Using your own target files
You can also use your own target files instead of updating `scylla_servers.yml`, using the `-s` for scylla target file.

```
./start-all.sh -s my_scylla_servers.yml -d data_dir
```

To automatically generate the target files, one can use the `genconfig.py` script.
Check the documentation for usage instructions.


#### node_exporter Installation
[node_exporter](https://github.com/prometheus/node_exporter) is an exporter of hardware and OS metrics such as disk space.

For a fully functional dashboard you need to have the node_exporter running on each of the nodes and configure the prometheus accordingly.

As part of Scylla installation, the `scylla_setup` script will prompt to install node_exporter. If you skipped that step, you could always install node_exporter later with the  `node_exporter_install` script.


`node_exporter_install` will download and install the node_exporter as a service.


For node_exporter users that use version 0.16 and higher and use their own Prometheus server, look at the node_exporter configuration section.

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
 
* You can supply multiple comma delimited versions, for example to load only 4.1 and 4.2 version:
 ```
 ./start-all.sh -v 4.1,4.2
 ```

* The master branch is called master, so to load 4.2 and master you would use:
 ```
 ./start-all.sh -v 4.2,master
 ```

* The latest version will be used by default.
___
**Note: The -d data_dir is optional, but without it, Prometheus will erase all data between runs.**


**For systems in production it is recommended to use an external directory.**
___

#### Prometheus Command Line Options and Retention Period
Check the documentation for a full list of command line option for [start-all.sh](http://scylladb.github.io/scylla-monitoring/master/start_all.html)
Prometheus retention time is set to two weeks by default, you can override it as well as other Prometheus configuration with the `-b` flag.

For example:
```
-b "-storage.tsdb.retention.time=30d"
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
The dashboard holds a drop-down menu at its upper left corner for disk and network interface.
You should choose the relevant disk and interface for the dashboard to show the graphs.

### Update Scylla servers to send metrics
See [here](https://github.com/scylladb/scylla/wiki/Monitor-Scylla-with-Prometheus-and-Grafana#14-and-later-instruction)

### Load original data to Prometheus server

Additional parameters:
  -d data_dir

Full commandline:

```
./start-all.sh -d path/to/data_dir
```

### Using your own Grafana installation

``` ./load-grafana``` is not currently being maintained, please follow the instruction in the documentation.

Some users who already have grafana installed can just upload the Scylla dashboards into your existing grafana environment.
This is possible using the `load-grafana.sh` script.

For example, if you have prometheus running at `192.168.0.1:9090`, and grafana at localhost's port `3000`, you can do:

```
./load-grafana.sh -p 192.168.0.1:9090 -g 3000
```

### Alertmanager
Prometheus [Alertmanager](https://prometheus.io/docs/alerting/alertmanager/) handles alerts that are generated by the Prometheus server.

Alerts are generated according to the [Alerting rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/).

The Alertmanager listens on port `9093` and you can use a web browser to connect to it.
