Some queries use Consistency Level: ALL
---------------------------------------
Scylla stores your data in ReplicationFactor of nodes (replicas). Typically, for a consistency level, each piece of information is stored in multiple replicas. A query's Consistency Level determines how many replicas will need to be queried before a reply is returned. 

Using consistency level ALL in a query requires **all** replicas to be available and will fail if a node is unavailable, resulting in reduced availability. This means that the client will not get a result in case **one** of the replicas is down or not responding, reducing the HA of the system.

Consistency level ALL should be used with care and should be accompanied with deep understanding and fall back mechanisms for node unavailability.
