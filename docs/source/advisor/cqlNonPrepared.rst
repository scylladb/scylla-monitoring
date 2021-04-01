Some queries are non-prepared
-----------------------------
`Prepared Statements`_ are an optimization that allows parsing a query only once and executing it multiple times with different concrete values.
As a rule of thumb, you should always favor prepared statements.

.. _`Prepared Statements`: https://docs.scylladb.com/getting-started/definitions/#prepared-statements