Advisor Alerts
==============
The Advisor is an entity in Scylla Monitoring that aims to find potential users' problems and advise on how to solve them.
Currently, it uses low-priority alerts as a notification method.
That means that for each potential issue, it will generate an alert.

Following is a list of such alerts, with their description break into sections.

CQL Optimization
^^^^^^^^^^^^^^^^
- cqlNonPrepared:Some queries are non-prepared
- cqlNonPaged:Some SELECT queries  are non-paged
- cqlNoTokenAware:Some queries are not token-aware
- cqlReverseOrder:Some queries use reverse order
- cqlAllowFiltering:Some queries use ALLOW FILTERING
- cqlCLAny:Some queries use Consistency Level: ANY
- cqlCLAll:Some queries use Consistency Level: ALL


Balanced
^^^^^^^^
- nonBalancedcqlTraffic:CQL queries are not balanced among shards

Ooperation Error
^^^^^^^^^^^^^^^^
- nodeLocalErrors:Some operation failed at the replica side
- nodeIOErrors:IO Errors can indicate a node with a faulty disk
- nodeCLErrors:Some operation failed due to consistency level

