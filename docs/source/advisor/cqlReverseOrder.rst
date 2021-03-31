Some queries use reverse order
------------------------------

Scylla supports a “cluster key” as a way to order (sort) rows in the same partition. 

Querying with an order reversed from the the order the CLUSTERING ORDER BY was defined is inefficient and more resource consuming and should be avoided if possible

Documentation link
^^^^^^^^^^^^^^^^^^
https://docs.scylladb.com/troubleshooting/reverse-queries/

