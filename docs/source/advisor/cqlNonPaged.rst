Some SELECT queries are non-paged
---------------------------------
By default, read queries are paged, this means that Scylla will break the results into multiple chunks (pages) limiting the reply size. Non-Paged queries require all results to be returned in one reply increasing the overall load on Scylla and drivers and clients should avoid them.

Blog-post Links
^^^^^^^^^^^^^^^
https://www.scylladb.com/2018/07/13/efficient-query-paging/

