Some queries use Consistency Level: ALL
---------------------------------------
Scylla stores your data in ReplicationFactor of nodes (replicas). Typically, for a consistency level, each piece of information is stored in multiple replicas. A query's Consistency Level determines how many replicas will need to be queried before a reply is returned. 

Using consistency level ALL in a query requires **all** replicas to be available and will fail if a node is unavailable, resulting in reduced availability. This means that the client will not get a result in case **one** of the replicas is down or not responding, reducing the HA of the system.

Consistency level ALL should be used with care and should be accompanied with deep understanding and fall back mechanisms for node unavailability.

Link to Scylla university
^^^^^^^^^^^^^^^^^^^^^^^^^
`Lesson on Consistency <https://university.scylladb.com/courses/scylla-essentials-overview/lessons/high-availability/topic/consistency-level/#:~:text=ALL%20%E2%80%93%20A%20write%20must%20be%20written%20to%20all%20replicas%20in%20the%20cluster%2C%20a%20read%20waits%20for%20a%20response%20from%20all%20replicas.%20Provides%20the%20lowest%20availability%20with%20the%20highest%20consistency.>`_
