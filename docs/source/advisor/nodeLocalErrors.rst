Some operations failed on the replica side
------------------------------------------
ScyllaDB uses data replication, that means that a query is sent to a coordinator node which in turn sends it to the replica nodes (the nodes that actually hold the replicated data) it then collects the replies and returns an answer.

Error on the replica side means that data failed to be persistent on that node, leaving data persistent at risk. Check the node to identify the reasons for the errors.
