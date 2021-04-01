Some queries use ALLOW FILTERING
--------------------------------
Scylla supports server-side data filtering that is not based on the primary key. This means Scylla would execute a *full scan* on the table: read **all** of the table's data from disk, and then filter and return part of it to the user.  More information on `ALLOW FILTERING <https://docs.scylladb.com/getting-started/dml/#allowing-filtering>`_. 

These kinds of queries can create a bigger load on Scylla, and should be used with care.
