==========================================
Lightweight Transactions Metrics Reference
==========================================

The Lightweight Transactions (LWT) Dashboard has many metrics. This table explains them.

.. list-table:: LWT Metrics
   :widths: 10 90
   :header-rows: 1

   * - Metric Name
     - Description
   * - scylla_storage_proxy_coordinator_cas_read_timeouts
     - Number of timeout exceptions when waiting for replicas during SELECTs with SERIAL consistency.
       This also includes timeouts waiting on internal Paxos semaphore, owned by the coordinator and associated with the key and timeouts caused by Paxos protocol retries, also known as Paxos contention.

       Replicas considered dead according to gossip are not included into Paxos peers, so the errors only happen for replicas which were contacted.
       Typically an indication of node overload or a particularly frequently accessed key.
   * - scylla_storage_proxy_coordinator_cas_write_timeouts
     - Number of timeout exceptions when waiting for replicas during UPDATEs, INSERTs and DELETEs with SERIAL consistency.
       This also includes timeouts waiting on internal Paxos semaphore, owned by the coordinator and associated with the key and timeouts caused by Paxos protocol retries, also known as Paxos contention.

       Replicas considered dead according to gossip are not included into Paxos peers, so the errors only happen for replicas which were contacted.
       Typically an indication of node overload or a particularly frequently updated key.
   * - scylla_storage_proxy_coordinator_cas_read_latency
     - Latency histogram for SELECTs with SERIAL consistency.
   * - scylla_storage_proxy_coordinator_cas_write_latency
     - Latency histogram for INSERTs, UPDATEs, DELETEs with SERIAL consistency.
   * - cql_inserts{conditional=yes}
     - Total number of CQL INSERT requests with conditions, e.g. INSERT … IF NOT EXISTS
   * - cql_updates{conditional=yes}
     - Total number of CQL UPDATE requests with conditions, for example UPDATE cf SET key = value WHERE pkey = pvalue IF EXISTS
   * - cql_deletes{conditional=yes}
     - Total number of CQL DELETE requests with conditions, e.g. DELETE … IF EXISTS
   * - cql_batches{conditional=yes}
     - Total number of CQL BATCH requests with conditions. If a batch request contains at least one conditional statement, the entire batch is counted as conditional.
   * - cql_statements_in_batches{conditional=yes}
     - Total number of statements in conditional CQL BATCHes. A CQL BATCH is conditional (atomic) if it contains at least one CQL statement with conditions. In this case all CQL statements in such a batch are accounted for in this metric.
   * - scylla_storage_proxy_coordinator_cas_write_condition_not_met
     - Total number of times INSERT, UPDATE or DELETE was not applied because the IF condition evaluated to False. Can be used as an indicator of data distribution.
   * - storage_proxy_coordinator_cas_read_contention
     - Total number of times some SELECT with SERIAL consistency had to retry because there was a concurrent conditional statement against the same key.
       Each retry is performed after a randomized sleep interval, so can lead to statement timing out completely. Indicates contention over a hot row or key.
   * - storage_proxy_coordinator_cas_write_contention
     - Total number of times some INSERT, UPDATE or DELETE request with conditions had to retry because there was a concurrent conditional statement against the same key.
       Each retry is performed after a randomized sleep interval, so can lead to statement timing out completely. Indicates contention over a hot row or key.
   * - scylla_storage_proxy_coordinator_cas_read_unavailable
     - Total number of times a SELECT with SERIAL consistency failed after being unable to contact a majority of replicas. Possible causes include network partitioning or a significant amount of down nodes.
   * - scylla_storage_proxy_coordinator_cas_write_unavailable
     - Total number of times an INSERT, UPDATE, or DELETE with conditions failed after being unable to contact a majority of replicas. Possible causes include network partitioning or a significant amount of down nodes.
   * - scylla_storage_proxy_coordinator_cas_write_timeout_due_to_uncertainty
     - Total number of partially succeeded conditional statements. These statements were not committed by the coordinator, due to some replicas responding with errors or timing out.
       The coordinator had to propagate the error to the client. However, the statement succeeded on a minority of replicas, so may later be propagated to the rest during repair.
   * - scylla_storage_proxy_coordinator_cas_read_unfinished_commit
     - Total number of Paxos repairs SELECTs statement with SERIAL consistency performed. A repair is necessary when a previous Paxos round did not complete.
       A subsequent statement then may not proceed before completing the work of its predecessor. A repair is not guaranteed to succeed, the metric indicates the number of repair attempts made.
   * - scylla_storage_proxy_coordinator_cas_write_unfinished_commit
     - Total number of Paxos repairs a conditional INSERT, UPDATE or DELETE statements consistency performed. A repair is necessary when a previous Paxos round did not complete.
       A subsequent statement then may not proceed before completing the work of its predecessor. A repair is not guaranteed to succeed, the metric indicates the number of repair attempts made.
   * - storage_proxy_coordinator_cas_failed_read_round_optimization
     - Normally a PREPARE Paxos round piggy-backs the previous value along with PREPARE response.
       This metric is incremented whenever the coordinator was not able to obtain the previous value (or its digest) from some of the participants, or when the digests did not match.
       A separate repair round has to be performed in this case. Indicates that some Paxos queries did not run successfully to completion, e.g. because some node is overloaded, down, or there was contention around a key.
   * - storage_proxy_coordinator_cas_prune
     - A successful conditional statement deletes the intermediate state from “system.paxos” table using “PRUNE” command. This metric reflects the total number of pruning requests executed on this replica.
   * - storage_proxy_coordinator_cas_dropped_prune
     - A successful conditional statement deletes the intermediate state from “system.paxos” table using “PRUNE” command.
       If the system is busy it may not keep up with the PRUNE requests, so such requests are throttled. This metric indicates the total number of throttled PRUNE requests.

       High value suggests the system is overloaded and also that system.paxos table is taking up space.
       If a prune is dropped, system.paxos table key and value for respective LWT transaction  will stay around until next transaction against the same key or gc_grace_period, when it's removed by compaction.
   * - cas_prepare_latency
     - Histogram of CAS PREPARE round latency for this table. Contributes to the overall conditional statement latency.
   * - cas_accept_latency
     - Histogram of CAS ACCEPT round latency for this table. Contributes to the overall conditional statement latency.
   * - cas_learn_latency
     - Histogram of CAS LEARN round latency for this table. Contributes to the overall conditional statement latency.