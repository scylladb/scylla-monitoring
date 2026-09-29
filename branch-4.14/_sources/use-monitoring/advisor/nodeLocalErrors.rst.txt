Some operations failed on the replica side
------------------------------------------
ScyllaDB uses data replication, which means that a query that is sent to a coordinator node sends the query to the replica nodes (the nodes that actually hold the replicated data). The coordinator then collects the replies and returns an answer.

An error on the replica side means that data failed to be persistent on that node, leaving data at risk. Check the node to identify the reasons for the errors.
