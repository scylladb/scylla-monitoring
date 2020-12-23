Using Thanos With Scylla Monitoring
============================

Scylla-Monitoring uses `Prometheus <https://prometheus.io/>`_ for metrics collection, which works out-of-the-box, but Prometheus does have limitations.
`Thanos <https://thanos.io/>`_  is an opensource solution on top of Prometheus with multiple functionalities it can:

1. Support high-availability.
2. Support horizontal scaling.
3. Support backup.

A nice thing with Thanos approach is its flexibility, you can use some of its functionality depends on your need.

Using Thanos As a Prometheus Aggregator
----------------------------------------------------------
There are a few reasons why you would need multiple Prometheus servers: if the total number of your time series reaches millions you can reach the limit of a single Prometheus server capacity.
Sometimes it is also useful to limit the traffic between data centers, so you can have a Prometheus server per DC.

Prometheus Configuration
^^^^^^^^^^^^^^^^^^^^^^^^^
We will assume you have two Prometheus servers running.

1. If you are running Prometheus using a container, you should use an **external** data directory, make sure it is reachable by other containers.
2. You will need to add the `--web.enable-lifecycle` flag to your Prometheus command-line option.

Thanos sidecar
^^^^^^^^^^^^^^^

The Thanos sidecar is an agent that read from a local Prometheus. Thanos uses a single docker container for different uses, the container would act
differently based on the command line it gets.
You will need a sidecar for each of your Prometheus servers.
A docker command looks like:

.. code-block:: shell

   docker run -d \
    -v /path/to/prom/dir:/data/prom:z \
    -i --name sidecar thanosio/thanos \
    sidecar \
    --grpc-address=0.0.0.0:10911 \
    --grpc-grace-period=1s \
    --http-address=0.0.0.0:10912 \
    --http-grace-period=1s \
    --prometheus.url=http://prometheus-ip:9090 \
    --tsdb.path=/data/prom \
    -p 10912:10912 \
    -p 10911:10911

After you run the sidecar you should be able to reach it from your browser at: http://{ip}:10912

Thanos query
^^^^^^^^^^^^
Thanos query is the aggregator, it expose a Prometheus like API and read from multiple thanos stores (in this case the Thanos stores are the sidecars).
You run thanos query together with Scylla monitoring. Assuming that you have two sidecars running on IP addresses: `ip1` and `ip2`,
you can start it like that: 

.. code-block:: shell

   docker run -d \
    --name thanos -- thanosio/thanos \
      query \
      --debug.name=query0 \
      --log.level=debug \
      --grpc-address=0.0.0.0:10903 \
      --grpc-grace-period=1s \
      --http-address=0.0.0.0:10904 \
      --http-grace-period=1s \
      --query.replica-label=prometheus \
      --store={ip1}:10911 --store={ip2}:10911

After you run Thanos query, you can connect to its http server, in the above example at http://{ip}:10903

Update Scylla Data source
^^^^^^^^^^^^^^^^^^^^^^^^^
Last you need to update the Grafana data source to read from the local Thanos instead of from Prometheus. Edit grafana/datasource.yml
and replace DB_ADDRESS with {ip}:10903 (The IP address could be of the container as long as it is reachable).

The file you edit is a template file that replaces the file Grafana uses, next time you start.

Restart the monitoring stack it should now uses Thanos 