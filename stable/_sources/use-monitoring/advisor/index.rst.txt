===============================
Scylla Monitoring Stack Advisor
===============================

.. toctree::
   :glob:
   :maxdepth: 1
   :hidden:

   *

The Scylla Monitoring Stack Advisor is an element of the Scylla Monitoring Stack that recognizes bad practices, bad configurations, and potential problems and advises on how to solve them.

For example, the Advisor could warn about using large cells. Large cells in the data usually indicate a problem with the data model or a problem with the client code, and can impact system performance.

Each Advisor issue is explained in detail:

* :doc:`Some queries use ALLOW FILTERING <cqlAllowFiltering>`
* :doc:`Some queries use Consistency Level: ALL <cqlCLAll>`
* :doc:`Some queries use Consistency Level: ANY <cqlCLAny>`
* :doc:`Some queries are not token-aware <cqlNoTokenAware>`
* :doc:`Some SELECT queries are non-paged <cqlNonPaged>`
* :doc:`Some queries are non-prepared <cqlNonPrepared>`
* :doc:`Some operation failed due to unsatisfied consistency level <nodeCLErrors>`
* :doc:`I/O Errors can indicate a node with a faulty disk <nodeIOErrors>`
* :doc:`Some operations failed on the replica side <nodeLocalErrors>`
* :doc:`CQL queries are not balanced among shards  <nonBalancedcqlTraffic>`
* :doc:`Prepared statements cache eviction <preparedCacheEviction>`
