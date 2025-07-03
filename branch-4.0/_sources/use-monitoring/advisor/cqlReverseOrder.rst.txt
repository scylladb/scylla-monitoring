Some queries use reverse order
------------------------------

Scylla supports a “cluster key” as a way to order (sort) rows in the same partition. 

Querying with an order which is different from the defined order in the CLUSTERING ORDER BY is inefficient and more resource-consuming. Reverse Queries should be avoided if possible

Documentation link
^^^^^^^^^^^^^^^^^^
https://docs.scylladb.com/troubleshooting/reverse-queries/
