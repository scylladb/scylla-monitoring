Minimal Production System Recommendations
-----------------------------------------

* **CPU** - For clusters with up to 100 cores use 2vCPUS, for larger clusters 4vCPUs
* **Memory** - 15GB+ DRAM and proportional to the number of cores.
* **Disk** - persistent disk storage is proportional to the number of cores and Prometheus retention period (see the following section)
* **Network** - 1GbE/10GbE preferred

Calculating Prometheus Minimal Disk Space requirement
.....................................................

Prometheus storage disk performance requirements: persistent block volume, for example an EC2 EBS volume

Prometheus storage disk volume requirement:  proportional to the number of metrics it holds and the default retention time. The default retention period is 15 days, and the disk requirement is around
|DISK_BYTES_PER_SERIES_PER_DAY| per series per day, assuming the default scraping interval of 20s.

For example, 100k series, with a retention time of 45 days, will need

..  parsed-literal::

   100k * |DISK_BYTES_PER_SERIES_PER_DAY| * 45 ~ |DISK_EXAMPLE|


To account for unexpected events, like replacing or adding nodes, we recommend allocating at least x2-3 the space, in this case, ~\ |DISK_EXAMPLE_HEADROOM|.
Prometheus Storage disk does not have to be as fast as Scylla disk, and EC2 EBS, for example, is fast enough and provides HA out of the box.

Calculating Prometheus Minimal Memory Space requirement
.......................................................

Prometheus uses more memory when querying over a longer duration (e.g. looking at a dashboard on a week view would take more memory than on an hourly duration).

For Prometheus alone, you should have |RSS_BYTES_PER_SERIES| of memory per series and it would use about 600MB of virtual memory per core.
Because Prometheus is so memory demanding, it is a good idea to add swap, so queries with a longer duration would not crash the server.

.. raw:: html

    <script>
        //   series     = SERIES_CONST + SERIES_PER_NODE*nodes + SERIES_PER_CORE*cores + ...  (cores = total cores)
        //   rss_bytes  = RSS_CONST_BYTES + RSS_BYTES_PER_SERIES*series
        //   disk_bytes = (DISK_CONST_BYTES_PER_DAY + DISK_BYTES_PER_SERIES_PER_DAY*series) * retention_days
        //                + WAL_CONST_BYTES + WAL_BYTES_PER_SERIES*series
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
            const cores = nodes * value('shards');
            const tables = value('tables');
            const active = Math.min(value('active_tables'), tables);
            const sl = value('service_levels');
            const alternator = value('alternator_tables');
            const retention = value('retention');

            const series = SERIES_CONST + SERIES_PER_NODE * nodes + SERIES_PER_CORE * cores
                + SERIES_PER_TABLE_PER_NODE * tables * nodes + SERIES_PER_ACTIVE_TABLE_PER_NODE * active * nodes
                + SERIES_PER_SL_PER_CORE * sl * cores + SERIES_PER_ALTERNATOR_TABLE_PER_NODE * alternator * nodes;
            const memory = RSS_CONST_BYTES + RSS_BYTES_PER_SERIES * series;
            const disk = (DISK_CONST_BYTES_PER_DAY + DISK_BYTES_PER_SERIES_PER_DAY * series) * retention
                + WAL_CONST_BYTES + WAL_BYTES_PER_SERIES * series;

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

.. Rounded values used in the text above, written by prometheus_sizing.py --update-doc.

.. |DISK_BYTES_PER_SERIES_PER_DAY| replace:: 3.5KB
.. |DISK_EXAMPLE| replace:: 15GB
.. |DISK_EXAMPLE_HEADROOM| replace:: 40GB
.. |RSS_BYTES_PER_SERIES| replace:: 16KB
