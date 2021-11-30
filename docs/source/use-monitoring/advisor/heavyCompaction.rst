Compaction takes lots of memory and CPU
---------------------------------------
Scylla runs compaction periodically as a background process. While running compaction is important, there are situations that
the compaction takes too much CPU.
In those cases the compaction would impact the overall system performance.

When facing this problem, you can statically limit the compaction shares with one of two options:

1. Change ``scylla.yml`` to have ``compaction_static_shares: 100`` 

or

2. Start scylla with ``--compaction-static-shares 100``