Using Docker Compose
====================

Scylla-Monitor is container-based, using Docker Compose file allows you to simplify starting and stopping the monitoring stack.

Prerequisite 
------------

Make sure you have `docker` and `docker-compose` installed.

Setting Prometheus
------------------

Prometheus configuration file contains among others the IP address of the alertmanager and either the location
of the `scylla_server.yml` file or a Consul IP address of Scylla-Manager, if Scylla-Manager is used for server provisioning.

You can use `./prometheus-config.sh` to generate the file, for example: 

.. code-block:: shell

   ./prometheus-config.sh --compose
   
For production usage, It is advice that you will use an external directory for the Prometheus database, make sure to create one and
update the docker-compose file accordingly (see the docker-compose example).  

Setting Grafana Provisioning
----------------------------

Grafana reads its provisioning configuration from files, one for the data-source and one
for the dashboards. Note that the latter tells Grafana where the dashboards are not the dashboard themselves that are
in a different location.

Grafana Data-Source file
^^^^^^^^^^^^^^^^^^^^^^^^
to update the datasource you can run

.. code-block:: shell

   ./grafana-datasource.sh --compose

You can see the generated file under: `grafana/provisioning/datasources/datasource.yaml` 

Grafana Dashboard Load file
^^^^^^^^^^^^^^^^^^^^^^^^^^^
To set the dashboard load file, you can use the `./generate-sashboards.sh` with the `-t` command line flag, for example
to use scylla-enterprise version 2020.1

.. code-block:: shell

   ./generate-dashboards.sh -t -v 2020.1

You can see the generated files `grafana/provisioning/dashboards/`

Docker Compose file
-------------------
You can use the following example as a base for your docker compose.

Pass the following to a file called `docker-compose.yml`


.. code-block:: yaml

    services:
      alertmanager:
        container_name: aalert
        image: prom/alertmanager:v0.21.0
        ports:
        - 9093:9093
        volumes:
        - ./prometheus/rule_config.yml:/etc/alertmanager/config.yml
      grafana:
        container_name: agraf
        environment:
        - GF_PANELS_DISABLE_SANITIZE_HTML=true
        - GF_PATHS_PROVISIONING=/var/lib/grafana/provisioning
        - GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=scylladb-scylla-datasource
        # This is where you set Grafana security
        - GF_AUTH_BASIC_ENABLED=false
        - GF_AUTH_ANONYMOUS_ENABLED=true
        - GF_AUTH_ANONYMOUS_ORG_ROLE=Admin
        - GF_SECURITY_ADMIN_PASSWORD=admin
        image: grafana/grafana:7.3.5
        ports:
        - 3000:3000
        user: 1000:1000
        volumes:
        - ./grafana/build:/var/lib/grafana/dashboards
        - ./grafana/plugins:/var/lib/grafana/plugins
        - ./grafana/provisioning:/var/lib/grafana/provisioning
        # Uncomment the following line for grafana persistency
        # - path/to/grafana/dir:/var/lib/grafana
      loki:
        command:
        - --config.file=/mnt/config/loki-config.yaml
        container_name: loki
        image: grafana/loki:2.0.0
        ports:
        - 3100:3100
        volumes:
        - ./loki/rules:/etc/loki/rules
        - ./loki/conf:/mnt/config
      promotheus:
        command:
        - --config.file=/etc/prometheus/prometheus.compose.yml
        container_name: aprom
        image: prom/prometheus:v2.18.1
        ports:
        - 9090:9090
        volumes:
        - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
        - ./prometheus/prometheus.rules.yml:/etc/prometheus/prometheus.rules.yml
        - ./prometheus/scylla_servers.yml:/etc/scylla.d/prometheus/scylla_servers.yml
        - ./prometheus/scylla_manager_servers.yml:/etc/scylla.d/prometheus/scylla_manager_servers.yml
        - ./prometheus/scylla_servers.yml:/etc/scylla.d/prometheus/node_exporter_servers.yml
        # Uncomment the following line for prometheus persistency 
        # - path/to/data/dir:/prometheus/data
      promtail:
        command:
        - --config.file=/etc/promtail/config.yml
        container_name: promtail
        image: grafana/promtail:2.0.0
        ports:
        - 1514:1514
        - 9080:9080
        volumes:
        - ./loki/promtail/promtail_config.compose.yml:/etc/promtail/config.yml
    version: '3'

Start and Stop
^^^^^^^^^^^^^^

use `docker-compose up` and `docker-compose down` to start and stop the monitoring stack. 