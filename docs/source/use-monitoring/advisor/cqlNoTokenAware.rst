Some queries are not token-aware
--------------------------------
Scylla is a distributed database, with each node containing only part of the data. Ideally, a query would reach the node that holds the data (one of the replicas). Failing to do so would mean the coordinator will need to send the query internally to a replica, resulting in higher latency and more resource usage.

Typically, your driver would know how to route the queries to a replication node, but if you're using non-prepared statements, a non-token-aware load-balance policy can cause the query to reach a node that is not a replica.

University link
^^^^^^^^^^^^^^^
https://university.scylladb.com/courses/using-scylla-drivers/lessons/intro-and-recap-token-ring-architecture/
