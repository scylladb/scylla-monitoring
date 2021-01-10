=========================
Scylla Monitoring Advisor
=========================

Scylla Advisor is an element of Scylla Monitoring that recognize bad practice, bad configuration, and potential problems and advice on how to solve them.

The Advisor section
^^^^^^^^^^^^^^^^^^^^
.. figure:: advisor_panel.png

    **The Advisor section**

The Advisor section is on the Overview dashboard and consists of two parts:
    
On the left, the Advisor issues table. Each issue has a category, a link to jump to a relevant dashboard, and a description of the issue.

For example, the Advisor would warn of large cells. Large cells in the data usually indicate a problem with the data model or a problem with the client code, impacting system performance.
    
On the right, the system balance section.  This section notifies for an imbalance between shards or nodes. An imbalanced system may indicate a potential problem.

For example, when a single, hot partition gets most of the requests, making one shard a bottleneck, the balance section will indicate that the latency and cache hits are imbalanced between shards.