===============================
Scylla Monitoring Stack Advisor
===============================

The Scylla Monitoring Stack Advisor is an element of the Scylla Monitoring Stack that recognize bad practices, bad configurations, and potential problems and advises on how to solve them.

The Advisor section
^^^^^^^^^^^^^^^^^^^^
.. figure:: advisor_panel.png

    **The Advisor section**

The Advisor section is located on the Overview dashboard and consists of two parts:
    
On the left, is the Advisor issues table. Each issue has a category, a link to jump to a relevant dashboard, and a description of the issue.

For example, the Advisor could warn about using large cells. Large cells in the data usually indicate a problem with the data model or a problem with the client code, and can impact system performance.
    
On the right, is the system balance section.  This section notifies you about an imbalance between shards or nodes. An imbalanced system may indicate a potential problem.

For example, when a single, hot partition gets most of the requests, making one shard a bottleneck, the balance section will indicate that the latency and cache hits are imbalanced between shards.