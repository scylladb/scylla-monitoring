=========================
Scylla Monitoring Advisor
=========================

The Advisor is both a concept and an implementation.


The advisor concept
^^^^^^^^^^^^^^^^^^^^^
The advisor looks for potential problems with the system,  with the setup, or with the data model and notify about it. The idea is to give insight into the information rather than general graphs.
This approach is used in the `CQL optimization section` and the advisor section.

.. _`CQL optimization section`: ./cql_optimization


The advisor section
^^^^^^^^^^^^^^^^^^^^
.. figure:: advisor_panel.png

    **The Advisor section**

The advisor section is on the Overview dashboard and consists of two parts.
On the left, there is a table with issues found by the advisor.
Each issue has a category, a dashboard quick link to jump to the relevant dashboard, and a description of the issue.
For example, the advisor would warn if there is a large cell in the data. A few large cells usually indicate a problem with the data model or a problem with the client code. This issue can have an impact on overall system performance.

On the right side, there is the system balance section. This section looks for outliers shards or nodes. If one shard behaves very differently from other shards, it indicates a problem with the system.
For example, in the case of hot-partition, where a single partition gets many requests and acts as a bottleneck, the balance section will indicate that the latency and cache hits differ between shards. 
