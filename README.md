# Scylla monitoring with Grafana and Prometheus

___
**Notice for users of Scylla versions prior to 1.4**


**If you are using a Scylla version before 1.4, or if you are using Prometheus over collectd, check out the v0.1 tag.**

`git checkout v0.1`
___
The monitoring infrastructure consists of several components, wrapped in Docker containers:
 * `prometheus` - collects and stores metrics
 * `grafana` - dashboard server

### Prerequisites
* git
* docker
* python module pyyaml (for `genconfig.py`)

On CentOS, you can do:

```bash
sudo yum install -y git docker python-pip
sudo pip install --upgrade pip
sudo pip install pyyaml
```

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

Update `prometheus/scylla_servers.yml` and `prometheus/node_exporter_servers.yml` with the targets (server you wish to monitor).
For every server, there are two targets, one under `scylla` job which is used for the scylla metrics.
Use port 9180.
For example, update targets in `prometheus/scylla_servers.yml` :

```
- targets:
  - 172.17.0.2:9180
  - 172.17.0.3:9180
```

Second, for general node information (disk, network, etc.) add the server under `node_exporter` job. Use port 9100.
For example, update targets in `prometheus/node_exporter_servers.yml` :

```
- targets:
  - 172.17.0.2:9100
  - 172.17.0.3:9100
```

You can also use your own target files instead of updating `scylla_servers.yml` and `node_exporter_servers.yml`, using the `-s` for scylla target file and `-n` for node taget file. For example:

```
./start-all.sh -s my_scylla_server.yml -n my_node_exporter_servers.yml -d data_dir
```

In many deployments the contents of those files are very similar, with the same servers being listed differing only in the ports scylla and node_exporter listen to. To automatically generate the target files, one can use the `genconfig.py` script, using the `-n` and `-s` flags to control which files get created:

```
./genconfig.py -ns -d myconf 192.168.0.1 192.168.0.2
```

After that, the monitoring stack can be started pointing to the servers at `192.168.0.1` and `192.168.0.2` with::

```
./start-all.sh -s myconf/scylla_server.yml -n myconf/node_exporter_servers.yml
```

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
