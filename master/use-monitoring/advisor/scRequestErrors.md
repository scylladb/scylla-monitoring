# Requests to strongly consistent tables fail

Each tablet of a strongly consistent table has its own Raft group. Writes and linearizable reads are routed to the leader of the group.

The alert fires when, for 5 minutes, more than 1% of the strongly consistent writes or reads that a node executes fail with the same reason, and more than 6 of them fail per minute. The second condition keeps a few failures on an almost idle node from raising the alert. The alert names the node, the operation and the reason:

* `timeout`: the leader may be overloaded, or the group may be electing a new leader.
* `status_unknown`: the write may or may not have been applied, for example because the leader changed while the write was being committed.
* `unavailable`: the node sees no live replica of the tablet.

Requests that fail for other reasons, such as a write over the size limit or a dropped table, do not count toward the alert.

The Strongly Consistent Tables sections of the Detailed dashboard show the elections, the retries and the Raft backpressure on that node.
