# Scylla Monitoring Stack Advisor

The Scylla Monitoring Stack Advisor is an element of the Scylla Monitoring Stack that recognizes bad practices, bad configurations, and potential problems and advises on how to solve them.

For example, the Advisor could warn about using large cells. Large cells in the data usually indicate a problem with the data model or a problem with the client code, and can impact system performance.

Each Advisor issue is explained in detail:

* [Some queries use ALLOW FILTERING](https://monitoring.docs.scylladb.com/master/use-monitoring/advisor/cqlAllowFiltering.md)
* [Some queries use Consistency Level: ALL](https://monitoring.docs.scylladb.com/master/use-monitoring/advisor/cqlCLAll.md)
* [Some queries use Consistency Level: ANY](https://monitoring.docs.scylladb.com/master/use-monitoring/advisor/cqlCLAny.md)
* [Some queries are not token-aware](https://monitoring.docs.scylladb.com/master/use-monitoring/advisor/cqlNoTokenAware.md)
* [Some SELECT queries are non-paged](https://monitoring.docs.scylladb.com/master/use-monitoring/advisor/cqlNonPaged.md)
* [Some queries are non-prepared](https://monitoring.docs.scylladb.com/master/use-monitoring/advisor/cqlNonPrepared.md)
* [Some operation failed due to unsatisfied consistency level](https://monitoring.docs.scylladb.com/master/use-monitoring/advisor/nodeCLErrors.md)
* [I/O Errors can indicate a node with a faulty disk](https://monitoring.docs.scylladb.com/master/use-monitoring/advisor/nodeIOErrors.md)
* [Some operations failed on the replica side](https://monitoring.docs.scylladb.com/master/use-monitoring/advisor/nodeLocalErrors.md)
* [CQL queries are not balanced among shards](https://monitoring.docs.scylladb.com/master/use-monitoring/advisor/nonBalancedcqlTraffic.md)
* [Prepared statements cache eviction](https://monitoring.docs.scylladb.com/master/use-monitoring/advisor/preparedCacheEviction.md)
