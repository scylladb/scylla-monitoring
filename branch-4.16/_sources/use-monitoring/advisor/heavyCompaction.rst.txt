Compaction takes lots of memory and CPU
---------------------------------------
ScyllaDB runs compaction periodically as a background process. While running compaction is important, there are situations when
compaction takes too much CPU.
As a result, compaction impacts the overall system performance.

If this is the case, you can do one of the following:

* Statically limit the compaction shares with the ``compaction_static_shares`` option by setting a value between 50 and 1000:

    * In the ``scylla.yml`` configuration file: ``compaction_static_shares: 100``
    * In the command line when starting ScyllaDB: ``--compaction-static-shares 100``
  
  You may start by setting the value ``100``. If read latency is impacted, which indicates that compaction is overly slowed down,
  you can increase the value to reach the balance between the system performance and read latency.

* Enforce ``min_threshold`` by setting ``compaction_enforce_min_threshold: true`` in the ``scylla.yml`` configuration file (`default is False <https://docs.scylladb.com/manual/stable/reference/configuration-parameters.html#confval-compaction_enforce_min_threshold>`_).
  As a result, ScyllaDB will compact only the buckets that contain the number of SSTables specified with ``min_threshold``
  or more. See `STCS options <https://docs.scylladb.com/getting-started/compaction/#stcs-options>`_ for details.

