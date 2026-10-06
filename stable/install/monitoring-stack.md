# Install Scylla Monitoring Stack

This document describes the setup of Scylla Monitoring Stack, based on [Prometheus API](https://monitoring.docs.scylladb.com/stable/reference/monitoring-apis.md#api-prometheus).

The Scylla Monitoring Stack needs to be installed on a dedicated server, external to the Scylla cluster. Make sure the Scylla Monitoring Stack server has access to the Scylla nodes so that it can pull the metrics over the Prometheus API.

For evaluation, you can run Scylla Monitoring Stack on any server (or laptop) that can handle three Docker instances at the same time. For production, see recommendations below.

## Minimal Production System Recommendations

* **CPU** - For clusters with up to 100 cores use 2vCPUS, for larger clusters 4vCPUs
* **Memory** - 15GB+ DRAM and proportional to the number of cores.
* **Disk** - persistent disk storage is proportional to the number of cores and Prometheus retention period (see the following section)
* **Network** - 1GbE/10GbE preferred

### Calculating Prometheus Minimal Disk Space requirement

Prometheus storage disk performance requirements: persistent block volume, for example an EC2 EBS volume

Prometheus storage disk volume requirement:  proportional to the number of metrics it holds and the default retention time. The default retention period is 15 days, and the disk requirement is around
3.5KB per series per day, assuming the default scraping interval of 20s.

For example, 100k series, with a retention time of 45 days, will need

```default
100k * 3.5KB * 45 ~ 15GB
```

To account for unexpected events, like replacing or adding nodes, we recommend allocating at least x2-3 the space, in this case, ~40GB.
Prometheus Storage disk does not have to be as fast as Scylla disk, and EC2 EBS, for example, is fast enough and provides HA out of the box.

### Calculating Prometheus Minimal Memory Space requirement

Prometheus uses more memory when querying over a longer duration (e.g. looking at a dashboard on a week view would take more memory than on an hourly duration).

For Prometheus alone, you should have 16KB of memory per series and it would use about 600MB of virtual memory per core.
Because Prometheus is so memory demanding, it is a good idea to add swap, so queries with a longer duration would not crash the server.

<script>
    //   series     = SERIES_CONST + SERIES_PER_NODE\*nodes + SERIES_PER_CORE\*cores + ...  (cores = total cores)
    //   rss_bytes  = RSS_CONST_BYTES + RSS_BYTES_PER_SERIES\*series
    //   disk_bytes = (DISK_CONST_BYTES_PER_DAY + DISK_BYTES_PER_SERIES_PER_DAY\*series) \* retention_days
    //                + WAL_CONST_BYTES + WAL_BYTES_PER_SERIES\*series
    const SERIES_CONST = 3786;
    const SERIES_PER_NODE = 1094;
    const SERIES_PER_CORE = 1185;
    const SERIES_PER_TABLE_PER_NODE = 17.86;
    const SERIES_PER_ACTIVE_TABLE_PER_NODE = 165.4;
    const SERIES_PER_SL_PER_CORE = 96.4;
    const SERIES_PER_ALTERNATOR_TABLE_PER_NODE = 20.9;
    const RSS_CONST_BYTES = 0;
    const RSS_BYTES_PER_SERIES = 16031;
    const DISK_CONST_BYTES_PER_DAY = 2096305;
    const DISK_BYTES_PER_SERIES_PER_DAY = 3574;
    const WAL_CONST_BYTES = 47523198;
    const WAL_BYTES_PER_SERIES = 2513;

    function formatBytes(bytes) {
        const units = ["B", "KB", "MB", "GB", "TB"];
        let i = 0;
        while (bytes >= 1024 && i < units.length - 1) {
            bytes /= 1024;
            i++;
        }
        return bytes.toFixed(i > 2 ? 2 : 0) + units[i];
    }

    function myFunction() {
        const value = (id) => parseInt(document.getElementById(id).value) || 0;
        const nodes = value('hosts');
        const cores = nodes \* value('shards');
        const tables = value('tables');
        const active = Math.min(value('active_tables'), tables);
        const sl = value('service_levels');
        const alternator = value('alternator_tables');
        const retention = value('retention');

        const series = SERIES_CONST + SERIES_PER_NODE \* nodes + SERIES_PER_CORE \* cores
            + SERIES_PER_TABLE_PER_NODE \* tables \* nodes + SERIES_PER_ACTIVE_TABLE_PER_NODE \* active \* nodes
            + SERIES_PER_SL_PER_CORE \* sl \* cores + SERIES_PER_ALTERNATOR_TABLE_PER_NODE \* alternator \* nodes;
        const memory = RSS_CONST_BYTES + RSS_BYTES_PER_SERIES \* series;
        const disk = (DISK_CONST_BYTES_PER_DAY + DISK_BYTES_PER_SERIES_PER_DAY \* series) \* retention
            + WAL_CONST_BYTES + WAL_BYTES_PER_SERIES \* series;

        document.getElementById('series').textContent = Math.round(series).toLocaleString();
        document.getElementById('memory').textContent = formatBytes(memory);
        document.getElementById('disk').textContent = formatBytes(disk);
    }
</script>
<div>
<table>
<tr><th># ScyllaDB Nodes</th><th># Cores Per ScyllaDB Node</th><th># Tables</th><th># Tables With Traffic</th><th># Service Levels</th><th># Alternator Tables</th><th>Prometheus Retention in Days</th></tr>
<tr>
<td><input type="number" id="hosts" oninput="myFunction()" value="3" placeholder="# Nodes" min="1"></td>
<td><input type="number" id="shards" oninput="myFunction()" value="16" placeholder="# Cores" min="1"></td>
<td><input type="number" id="tables" oninput="myFunction()" value="16" placeholder="# Tables" min="1"></td>
<td><input type="number" id="active_tables" oninput="myFunction()" value="16" placeholder="# Tables with traffic" min="0"></td>
<td><input type="number" id="service_levels" oninput="myFunction()" value="1" placeholder="# Service levels" min="1"></td>
<td><input type="number" id="alternator_tables" oninput="myFunction()" value="0" placeholder="# Alternator tables" min="0"></td>
<td><input type="number" id="retention" oninput="myFunction()" value="15" placeholder="# Days" min="1"></td>
</tr>
</table>
<table>
<tr><th># Series</th><th>Prometheus RAM</th><th>Prometheus Storage</th></tr>
<tr>
<td style="text-align:center"><span id="series">0</span></td>
<td style="text-align:center"><span id="memory">0</span></td>
<td style="text-align:center"><span id="disk">0</span></td>
</tr>
</table>
</div>
<script>
myFunction();
</script>
* **# Tables With Traffic** - tables that had reads or writes recently. Per-table latency histograms exist only for these tables, so they add many more series than idle tables.
* **# Service Levels** - user service levels, not counting the internal driver service level.

<!-- Rounded values used in the text above, written by prometheus_sizing.py --update-doc. -->

<a id="monitoring-stack-prerequisites"></a>

## Prerequisites

* Follow the Installation Guide and install [docker](https://docs.docker.com/install/) on the Scylla Monitoring Stack Server. This server can be the same server that is running Scylla Manager. Alternatively, you can [Deploy Scylla Monitoring Stack Without Docker](https://monitoring.docs.scylladb.com/stable/install/monitor-without-docker.md).
* If you have Prometheus or Grafana installed, confirm that your version is supported by the Scylla Monitoring Stack version you want to install. Refer to the table below.

#### Scylla Monitoring Stack Compatibility Matrix

| Scylla Monitoring Stack Version   | Prometheus Version   | Grafana Version   |
|-----------------------------------|----------------------|-------------------|
| 4.16                              | 3.12.0               | 13.2.0            |
| 4.15                              | 3.11.3               | 12.4.3            |
| 4.14                              | 3.9.1                | 12.3.2            |
| 4.13                              | 3.8.1                | 12.3.1            |
| 4.12                              | 3.5.0                | 12.1.1            |
| 4.11                              | 3.4.1                | 12.0.2            |
| 4.10                              | 3.3.1                | 11.6.1            |
| 4.9                               | 3.1.0                | 11.4.0            |
| 4.8                               | 2.53.1               | 11.1.0            |
| 4.7                               | 2.50.1               | 11.0.0            |
| 4.6                               | 2.48.1               | 10.2.2            |
| 4.5                               | 2.47.1               | 10.1.5            |
| 4.4                               | 2.44.0               | 9.5.2             |
| 4.3                               | 2.42.0               | 9.3.8             |
| 4.2                               | 2.41.0               | 9.3.4             |
| 4.1                               | 2.38.0               | 9.1.0             |
| 4.0                               | 2.34.0               | 8.5.2             |
| 3.11                              | 2.32.0               | 8.3.4             |
| 3.10                              | 2.32.0               | 8.3.3             |
| 3.9.2                             | 2.29.1               | 8.2.7             |
| 3.9                               | 2.29.1               | 8.1.1             |
| 3.8                               | 2.27.1               | 7.5.7             |
| 3.7                               | 2.25.2               | 7.4.0             |
| 3.6                               | 2.18.1               | 7.3.5             |
| 3.5                               | 2.18.1               | 7.1.5             |
| 3.4                               | 2.18.1               | 6.7.3             |

<a id="docker-post-installation"></a>

## Docker Post Installation

Docker post installation guide can be found [here](https://docs.docker.com/install/linux/linux-postinstall/)

#### NOTE
Avoid running the container as root.

To avoid running docker as root, you should add the user you are going to use for Scylla Monitoring Stack to the Docker group.

1. Create the Docker group.

```sh
sudo groupadd docker
```

1. Add your user to the docker group. Log out and log in again. The new group will be active for this user on next login.

```sh
sudo usermod -aG docker $USER
```

1. Start Docker by calling:

```sh
sudo systemctl enable docker
```

## Install Scylla Monitoring Stack

**Procedure**

1. Download and extract the latest [Scylla Monitoring Stack binary](https://github.com/scylladb/scylla-monitoring/releases);.

```sh
wget https://github.com/scylladb/scylla-monitoring/archive/4.16.1.tar.gz
tar -xvf 4.16.1.tar.gz
cd scylla-monitoring-4.16.1
```

As an alternative, you can clone and use the Git repository directly.

```sh
git clone https://github.com/scylladb/scylla-monitoring.git
cd scylla-monitoring
git checkout branch-4.16
```

1. Start Docker service if needed

```sh
sudo systemctl restart docker
```

## Configure Scylla Monitoring Stack

To monitor the cluster, Scylla Monitoring Stack (Specifically the Prometheus Server) needs to know the IP of all the nodes and the IP of the Scylla Manager Server (if you are using Scylla Manager).

This configuration can be done from files, or using the [Consul](https://www.consul.io/) api.

Scylla Manager 2.0 and higher supports the Consul API.

### Configure Scylla nodes from files

1. Create `prometheus/scylla_servers.yml` with the targets’ IPs (the servers you wish to monitor).

#### NOTE
It is important that the name listed in `dc` in the `labels` matches the datacenter names used by Scylla.
Use the `nodetool status` command to validate the datacenter names used by Scylla.

For example:

```yaml
- targets:
      - 172.17.0.2
      - 172.17.0.3
  labels:
      cluster: cluster1
      dc: dc1
```

#### NOTE
If you want to add your managed cluster to Scylla Monitoring Stack, add the IPs of the nodes as well as the cluster name you used when you [added the cluster](https://manager.docs.scylladb.com/stable/add-a-cluster.html) to Scylla Manager. It is important that the label `cluster name` and the cluster name in Scylla Manager match.

*Using IPV6*

To use IPv6 inside scylla_server.yml, add the IPv6 addresses with their square brackets.

For example:

```yaml
- targets:
      - "[2600:1f18:26b1:3a00:fac8:118e:9199:67b9]"
      - "[2600:1f18:26b1:3a00:fac8:118e:9199:67ba]"
  labels:
      cluster: cluster1
      dc: dc1
```

#### NOTE
For IPv6 to work, both scylla Prometheus address and node_exporter’s –web.listen-address should be set to listen to an IPv6 address.

For general node information (disk, network, etc.) Scylla Monitoring Stack uses the `node_exporter` agent that runs on the same machine as Scylla does.
By default, Prometheus will assume you have a `node_exporter` running on each machine. If this is not the case, for example if Scylla runs in a container and the node_exporter runs on the host, you can override the `node_exporter`
targets configuration file by creating an additional file and passing it with the `-n` flag.

#### NOTE
By default, there is no need to create `node_exporter_server.yml`. Prometheus will use the same targets it uses for
Scylla and will assume you have a `node_exporter` running on each Scylla server.

If needed, you can set your own target file instead of the default `prometheus/scylla_servers.yml`, using the `-s` for Scylla target files.

For example:

```yaml
./start-all.sh -s my_scylla_server.yml -d prometheus_data
```

Mark the different Data Centers with Labels.

As can be seen in the examples, each target has its own set of labels to mark the cluster name and the data center (dc).
You can add multiple targets in the same file for multiple clusters or multiple data centers.

You can use the `genconfig.py` script to generate the server file. For example:

```yaml
./genconfig.py -d myconf -dc dc1:192.168.0.1,192.168.0.2 -dc dc2:192.168.0.3,192.168.0.4
```

This will generate a server file for four servers in two datacenters server `192.168.0.1` and `192.168.0.2` in dc1 and `192.168.0.3` and `192.168.0.4` in dc2.

OR

The `genconfig.py` script can also use `nodetool status` to generate the server file using the `-NS` flag.

```yaml
nodetool status | ./genconfig.py -NS
```

2. Connect to [Scylla Manager](https://scylladb.github.io/scylla-manager/) by creating `prometheus/scylla_manager_servers.yml`
If you are using Scylla Manager, you should set its IP and port in this file.

You must add a scylla_manager_servers.yml file even if you are not using the manager.
You can look at: `prometheus/scylla_manager_servers.example.yml` for an example.

For example if Scylla Manager host IP is 172.17.0.7 `prometheus/scylla_manager_servers.yml` would look like:

```yaml
# List Scylla Manager end points

- targets:
  - 172.17.0.7:5090
```

Note that you do not need to add labels to the Scylla Manager targets.

### Configure Scylla nodes using Scylla-Manager Consul API

Scylla Manager 2.0 has a [Consul](https://www.consul.io/) like API.

When using the manager as the configuration source, there is no need  to set any of the files.
Instead you should set the scylla-manager IP from the command line using the -L flag.

For example:

```yaml
./start-all.sh -L 10.10.0.1
```

#### NOTE
If you are running Scylla-Manager on the same host as Scylla-Monitoring you should use -l flag so that the localhost address
will be available from within the container.

### Connecting Scylla-Monitoring to ScyllaDB

Scylla-Monitoring version 3.5 and higher can read tables from a ScyllaDB node using CQL. If your ScyllaDB cluster is user/password protected (See [Scylla  Authorization](https://docs.scylladb.com/operating-scylla/security/enable-authorization/)) you should assign a user and password for the Scylla-Grafana connection.

You can limit the user to read only, currently it only read table from the system keyspace.

You can set a user and password from a file or environment variables.

If the environment variables **SCYLLA_USER** and  **SCYLLA_PSSWD** are set, they will be used.

To set the user and password from a file, edit grafana/datasource.scylla.yml. Uncomment the **secureJsonData** part and set the user and password.

#### NOTE
It is best to use a dedicated user and password with limited privileges.

### Use an external directory for the Prometheus data directory

The `-d` flag, places the Prometheus data directory outside of its container and by doing that makes it persistent.

#### NOTE
Specifying an external directory is important for systems in production. Without it,
every restart of the monitoring stack will result in metrics lost.

If the directory provided does not exist, the `start-all.sh` script will create it. Note that you should avoid running docker as root, the `start-all.sh` script
will use the user permissions that runs it. This is important if you want to place the prometheus directory not under the user path but somewhere else, for example `/prometheus-data`.

In that case, you need to create the directory before calling `start-all.sh` and make sure it has the right permissions for the user running the command.

### Add Additional Prometheus Targets

There are situations where you would like to monitor additional targets using the Prometheus server of the monitoring stack.
For example, an agent that runs on a firewall server.
The Prometheus server reads its targets from a file, this file is generated from a template when calling `start-all.sh`.
To add your targets you would need to edit the template file before calling `start-all.sh`.

The template file is either `prometheus/prometheus.yml.template` if Prometheus reads the Scylla target from file, or `prometheus/prometheus.consul.yml.template`
if Prometheus gets Scylla targets from the manager Consul API.

You can add a target at the end of the file, for example, the following example would read from a server with IP address 17.0.0.1 with a Prometheus port of 7000.

```yaml
- job_name: 'myservice'
  # Override the global default and scrape targets from this job every 5 seconds.
  scrape_interval: 5s
  static_configs:
    - targets:
      - 17.0.0.1:7000
```

## Start and Stop Scylla Monitoring Stack

### Start

```yaml
./start-all.sh -d prometheus_data
```

### Stop

```yaml
./kill-all.sh
```

### Start a Specific Scylla Monitoring Stack Version

By default, start-all.sh will start with dashboards for the latest Scylla Open source version and the latest Scylla Manager version.

You can specify specific scylla version with the `-v` flag and Scylla Manager version with `-M` flag.

Multiple versions are supported. For example:

```sh
./start-all.sh -v 2020.1,2019.1 -M 2.1 -d prometheus-data
```

will load the dashboards for Scylla Enterprise versions `2020.1` and `2019.1` and the dashboard for Scylla Manager `2.1`

### Accessing the localhost

The Prometheus server runs inside a Docker container if it needs to reach a target on the local- host: either Scylla or Scylla-Manager, it needs to use the host network and not the Docker network.
To do that run ./start-all.sh with the -l flag. For example:

```sh
./start-all.sh -l -d prometheus-data
```

### Configure rsyslog on each Scylla node

generates metrics and alerts from logs. To get full functionality, you should use [rsyslog](https://www.rsyslog.com/). Scylla Monitoring Stack will act as an additional rsyslog server.
Scylla Monitoring Stack collects Scylla logs using Loki and generates metrics and alerts based on these logs.
To use this feature, you need to direct logs from each Scylla node to Loki.
The recommended method to do this is by using [rsyslog](https://www.rsyslog.com/), where Scylla Monitoring Stack (Loki) acts as an additional rsyslog server.
.. note:: Scylla can send logs to more than one log collection service.

**Prerequisite**, make sure rsyslog is installed and running. If rsyslog is not installed, follow the installation [instruction](https://www.rsyslog.com/doc/v8-stable/installation/index.html).

Add scylla’s rsyslog configuration file. Add the file: `/etc/rsyslog.d/scylla.conf`.

If Scylla Monitoring Stack IP is 10.0.0.1, the file should look like

```sh
if $programname ==  'scylla' then @@10.0.0.1:1514;RSYSLOG_SyslogProtocol23Format
```

Restart rsyslog for the configuration to take effect.

```sh
systemctl restart rsyslog
```

## View Grafana Dashboards

Point your browser to `your-server-ip:3000`
By default, Grafana authentication is disabled. To enable it and set a password for user admin use the `-a` option.

Iframe embedding is disabled by default. Use `--allow-embedding`, set `GF_SECURITY_ALLOW_EMBEDDING=true` in the environment or in `env.sh`, to enable it. Cross-origin embedding requires HTTPS.
See [The start-all.sh Command](https://monitoring.docs.scylladb.com/stable/install/start-all.md) for details.
