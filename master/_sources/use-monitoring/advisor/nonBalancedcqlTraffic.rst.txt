CQL queries are not balanced among shards 
-----------------------------------------
For optimal performance, data and queries should be distributed evenly across nodes and shards. If some shards are getting more traffic they could become a bottleneck for Scylla.

There could be multiple explanations for these performance issues: data-model, non-prepared statement, or driver.

Blog post link
^^^^^^^^^^^^^^
https://www.scylladb.com/2019/08/20/best-practices-for-data-modeling/
