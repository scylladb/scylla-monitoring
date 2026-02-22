Some operation failed due to unsatisfied consistency level
----------------------------------------------------------
ScyllaDB uses data replication, which means that a query is sent to a coordinator node sends the query to the replica nodes (the nodes that hold and persist the replicated data). The coordinator collects the replies and returns an answer. A query `Consistency Level`_, determines the number of replicas that must reply before the coordinator returns an answer.

.. _`Consistency Level`: https://docs.scylladb.com/glossary/#term-consistency-level-cl

For example, if the data is replicated to 3 nodes (AKA replication factor 3) and the Consistency Level is quorum, the coordinator will wait for 2 replies before returning the answer.

When one or more nodes are down or unreachable, the Coordinator may fail with a Consistency Level Error because it cannot reach the required consistency level.
