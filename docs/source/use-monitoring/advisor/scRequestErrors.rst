Requests to strongly consistent tables fail
-------------------------------------------
A strongly consistent table keeps each of its tablets in a Raft group of its own. Only the leader of the group executes writes and linearizable reads, and a write succeeds once it is in the Raft log of a majority of the tablet's replicas.

The alert fires when, for five minutes, more than 1% of the strongly consistent writes or reads that a node executes fail with the same reason, and more than six of them fail per minute. The second condition keeps a few failures on an almost idle node from raising the alert. The alert names the node, the operation and the reason:

* ``timeout``: the request did not finish in time. The leader may be overloaded, or the group may be electing a new leader.
* ``status_unknown``: the write may or may not have been applied, for example because the leader changed while the write was being committed. The client cannot tell whether the write took effect.
* ``unavailable``: no replica of the tablet is alive.

Requests that fail for other reasons, such as a write over the size limit or a table dropped while the request ran, do not count toward the alert.

The Strong Consistency dashboard shows the elections, the retries and the Raft backpressure on that node.
