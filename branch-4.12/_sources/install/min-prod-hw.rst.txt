Minimal Production System Recommendations
-----------------------------------------

* **CPU** - For clusters with up to 100 cores use 2vCPUS, for larger clusters 4vCPUs
* **Memory** - 15GB+ DRAM and proportional to the number of cores.
* **Disk** - persistent disk storage is proportional to the number of cores and Prometheus retention period (see the following section)
* **Network** - 1GbE/10GbE preferred

Calculating Prometheus Minimal Disk Space requirement
.....................................................

Prometheus storage disk performance requirements: persistent block volume, for example an EC2 EBS volume

Prometheus storage disk volume requirement:  proportional to the number of metrics it holds. The default retention period is 15 days, and the disk requirement is around 12MB per core per day, assuming the default scraping interval of 20s.

For example, when monitoring a 6 node Scylla cluster, each with 16 CPU cores (so a total of 96 cores), and using the default 15 days retention time, you will need **minimal** disk space for prometheus of

..  code::

   6 * 16 * 15 * 12MB ~ 16GB


To account for unexpected events, like replacing or adding nodes, we recommend allocating at least x2-3 space, in this case, ~50GB.
Prometheus Storage disk does not have to be as fast as Scylla disk, and EC2 EBS, for example, is fast enough and provides HA out of the box.

Calculating Prometheus Minimal Memory Space requirement
.......................................................

Prometheus uses more memory when querying over a longer duration (e.g. looking at a dashboard on a week view would take more memory than on an hourly duration).

For Prometheus alone, you should have 60MB of memory per core in the cluster and it would use about 600MB of virtual memory per core.
Because Prometheus is so memory demanding, it is a good idea to add swap, so queries with a longer duration would not crash the server.

.. raw:: html

    <script>
        function myFunction() {
            const hosts = parseInt(document.getElementById('hosts').value);
            const shards = parseInt(document.getElementById('shards').value);
            const retention = parseInt(document.getElementById('retention').value);
            let memory= (hosts*shards*60);
            let disk = (hosts*shards*retention*12);

            if (!Number.isNaN(disk)) {
                disk = (disk > 1024)?((disk/1024).toFixed(2) + "GB") : disk.toString() + "MB";
            } else {
               disk = "0";
            }
            document.getElementById('disk').textContent = disk;
            if (!Number.isNaN(memory)) {
                memory = (memory > 1024)?((memory/1024).toFixed(2) + "GB") : memory.toString() + "MB";
            } else {
                memory = "0";
            }
            document.getElementById('memory').textContent = memory;
        }
    </script>
    <div>
    <table>
    <colgroup>
    <col style="width: 20%">
    <col style="width: 20%">
    <col style="width: 20%">
    <col style="width: 20%;text-align: center;">
    <col style="width: 20%;text-align: center;">
    </colgroup>
    <tr><th># ScyllaDB Nodes</th><th># Cores Per ScyllaDB Node</th><th>Prometheus Retention in Days</th><th>Prometheus RAM</th><th>Prometheus Storage</th></tr>
    <tr><td><input type="number" id="hosts" onchange="myFunction()" value="3" placeholder="# Nodes" min="1"></td><td><input type="number" id="shards" onchange="myFunction()" value="16" placeholder="# Cores" min="1"></td><td><input type="number" id="retention" placeholder="# Days" onchange="myFunction()" value="15" min="1"></td><td style="text-align:center"><span id="memory" style="text-align:center">0</span></td><td style="text-align: center"><span id="disk">0</span></td></tr>

    </table>

    </div>
    <script>
    myFunction();
    </script>