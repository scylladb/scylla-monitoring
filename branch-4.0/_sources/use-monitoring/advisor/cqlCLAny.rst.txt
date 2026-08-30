Some queries use Consistency Level: ANY
---------------------------------------

Scylla stores your data in ReplicationFactor of nodes (replicas). A write query Consistency Level determines how many replicas need to acknowledge the write before a reply is returned.

Using consistency level ANY allows a write query to be acknowledged after storing the information on the coordinator, a non-replica (as hints), meaning the data will be acknowledged when in fact it is not yet persistent on disk. Use Consistency Level ANY with care. 

Link to Scylla university
^^^^^^^^^^^^^^^^^^^^^^^^^
`Lesson on Consistency <https://university.scylladb.com/courses/scylla-essentials-overview/lessons/high-availability/topic/consistency-level/#:~:text=Some%20of%20the%20most%20common,availability%20with%20the%20lowest%20consistency.>`_
