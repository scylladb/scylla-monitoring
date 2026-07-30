# Using Docker Compose

Scylla-Monitoring Stack is container-based.
You can start and stop the Scylla Monitoring Stack with the start-all.sh and kill-all.sh scripts.

Docker Compose is an alternative method to start and stop the stack. It requires more manual steps, but once
configured, it simplifies starting and stopping the stack.

#### WARNING
*docker-compose up* **and** *start-all.sh* are two **alternative** ways to launch Scylla Monitoring Stack.
You should use **one** method, **not both**. In particular,  creating and updating *docker-compose.yml* is ignored
when using *start_all.sh*

#### NOTE
There is an experimental method that uses scripts to create the Docker Compose file. See the details below.

## Prerequisite

Make sure you have docker and docker-compose installed.

## Experimental - Configure docker-compose file using scripts

The `make-compose.sh` script accepts the same command-line arguments as `start-all.sh`. It generates a `docker-compose.yaml` file and a `.env` file.

Once the script is run, you can use `docker-compose up` to start the monitoring stack.
You can manually modify the generated Compose file, but be aware that running `make-compose.sh` script again, will overwrite it.

There is also an experimental `--compose` command-line option for `start-all.sh`. It will first, generates the Compose file
and then uses docker-compose to run the monitoring stack.

## Setting Prometheus

The Prometheus configuration file contains among others the IP address of the *alertmanager* and either the location
of the *scylla_server.yml* file or a Consul IP address of Scylla Manager, if Scylla Manager is used for server provisioning.

You can use ./prometheus-config.sh to generate the file, for example:

```shell
./prometheus-config.sh --compose
```

For production systems, It is advised to use an external directory for the Prometheus database. Make sure to create one and
update the docker-compose file accordingly (see the docker-compose example below).

## Setting Grafana Provisioning

Grafana reads its provisioning configuration from files, one for the data-source and one for the dashboards.
Note that the latter tells Grafana where the dashboards are located, it is not the dashboards themselves, which are
at a different location.

By default, Grafana iframe embedding is disabled. The generated `docker-compose.yml` and `.env` files
include `GF_SECURITY_ALLOW_EMBEDDING`, `GF_SECURITY_COOKIE_SECURE`, and `GF_SECURITY_COOKIE_SAMESITE`.
Use `--allow-embedding` or set `GF_SECURITY_ALLOW_EMBEDDING=true` in `env.sh` to enable embedding.

### Grafana Data-Source file

Run the following command to update the datasource:

```shell
./grafana-datasource.sh --compose
```

You can see the generated file under: grafana/provisioning/datasources/datasource.yaml

### Grafana Dashboard Load file

To set the dashboard load file, you can run the ./generate-sashboards.sh with the -t command line flag and the -v flag to specify the version.
For example, Scylla-enterprise version 2020.1:

```shell
./generate-dashboards.sh -t -v 2020.1
```

This command generates the files under: grafana/provisioning/dashboards/

## Docker Compose file

You can use the following example as a base for your docker compose.

Pass the following to a file called docker-compose.yml

```ruby
services:
  alertmanager:
    container_name: aalert
    image: prom/alertmanager:v0.33.0
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
    # To set your home dashboard uncomment the following line, set VERSION to be your current version
    #- GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/var/lib/grafana/dashboards/ver_VERSION/scylla-overview.VERSION.json
    image: grafana/grafana:13.0.3
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
    image: grafana/loki:3.7.3
    ports:
    - 3100:3100
    volumes:
    - ./loki/rules:/etc/loki/rules
    - ./loki/conf:/mnt/config
  promotheus:
    command:
    - --config.file=/etc/prometheus/prometheus.yml
    container_name: aprom
    image: prom/prometheus:v3.12.0
    ports:
    - 9090:9090
    volumes:
    - ./prometheus/build/prometheus.yml:/etc/prometheus/prometheus.yml
    - ./prometheus/prom_rules/:/etc/prometheus/prom_rules/
    # instead of the following three targets, you can place three files under one directory and mount that directory
    # If you do, uncomment the following line and delete the three lines afterwards
    #- /path/to/targets:/etc/scylla.d/prometheus/targets/
    - ./prometheus/scylla_servers.yml:/etc/scylla.d/prometheus/targets/scylla_servers.yml
    - ./prometheus/scylla_manager_servers.yml:/etc/scylla.d/prometheus/targets/scylla_manager_servers.yml
    - ./prometheus/scylla_servers.yml:/etc/scylla.d/prometheus/targets/node_exporter_servers.yml
    
    # Uncomment the following line for prometheus persistency 
    # - path/to/data/dir:/prometheus/data
  promtail:
    command:
    - --config.file=/etc/promtail/config.yml
    container_name: promtail
    image: grafana/promtail:3.7.3
    ports:
    - 1514:1514
    - 9080:9080
    volumes:
    - ./loki/promtail/promtail_config.compose.yml:/etc/promtail/config.yml
version: '3'
```

### Start and Stop

To start the Scylla Monitoring Stack run `docker-compose up` and to stop run `docker-compose down`.
