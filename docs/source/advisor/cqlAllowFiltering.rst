Some queries use ALLOW FILTERING
--------------------------------
Scylla supports server side data filtering that is not based on the primary key. This means Scylla would execute a “full scan” on the table: read *all* the table data from disk, and then filter and return part of it to the user. 

These kinds of queries can create a bigger load on Scylla, and should be used with care.

