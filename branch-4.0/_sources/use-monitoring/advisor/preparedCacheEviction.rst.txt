Prepared statements cache eviction
---------------------------------------

Typically, prepared statements are prepared once and then used for a long period. Prepared statements are stored in the cache and only get evicted if they are not used.
If the prepared statements cache does get evicted, it's an indication that something is wrong.
The two main sources are:

* A prepared statement that contains a field value, creating such a statement will result in a new prepared statement being stored each time, which defies the purpose of it.
* The prepared statements cache might be too small for the number of prepared statements.

