#!/usr/bin/env bash

. versions.sh
VERSIONS=$DEFAULT_VERSION
usage="$(basename "$0") [-h] [-d Prometheus data-dir] [-v comma seperated versions] [-g grafana port ] [ -p prometheus port ] [-n comma separated list of nodes to monitor ] -- starts Grafana and Prometheus Docker instances"

GRAFANA_VERSION=4.1.1
PROMETHEUS_VERSION=v1.5.2

while getopts ':hd:g:p:v:n:' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    v) VERSIONS=$OPTARG
       ;;
    d) DATA_DIR=$OPTARG
       ;;
    g) GRAFANA_PORT=$OPTARG
       ;;
    p) PROMETHEUS_PORT=$OPTARG
       ;;
    n) NODES=$OPTARG
       ;;
    :) printf "missing argument for -%s\n" "$OPTARG" >&2
       echo "$usage" >&2
       exit 1
       ;;
   \?) printf "illegal option: -%s\n" "$OPTARG" >&2
       echo "$usage" >&2
       exit 1
       ;;
  esac
done

if [ -z $GRAFANA_PORT ]; then
    GRAFANA_PORT=3000
    GRAFANA_NAME=agraf
else
    GRAFANA_NAME=agraf-$GRAFANA_PORT
fi
if [ -z $PROMETHEUS_PORT ]; then
    PROMETHEUS_PORT=9090
    PROMETHEUS_NAME=aprom
else
    PROMETHEUS_NAME=aprom-$PROMETHEUS_PORT
fi

if [ -z $NODES ]; then
    NODES="127.0.0.1"
fi
# Don't put in a temporary location. The file needs to be still present if we are
# to restart the container upon reboot (for example)
SCYLLA_NODES_FILE="$PWD/prometheus/scylla_servers-$PROMETHEUS_PORT.yml"
NODE_EXPORTER_NODES_FILE="$PWD/prometheus/node_exporter_servers-$PROMETHEUS_PORT.yml"
python gen-prometheus.py $NODES 9180 > $SCYLLA_NODES_FILE
python gen-prometheus.py $NODES 9100 > $NODE_EXPORTER_NODES_FILE

# Exit if Docker engine is not running
if [ ! "$(sudo docker ps)" ]
then
        echo "Error: Docker engine is not running"
        exit 1
fi

if [ -z $DATA_DIR ]; then
    DATADIR=""
else
    echo "Loading prometheus data from $DATA_DIR"
    DATADIR="-v $DATA_DIR:/prometheus:Z"
fi

# Note: list files with -v individually, because different containers will be
# monitoring different nodes.
sudo docker run -d \
    -v $PWD/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:Z \
    -v $SCYLLA_NODES_FILE:/etc/prometheus/scylla_servers.yml:Z \
    -v $NODE_EXPORTER_NODES_FILE:/etc/prometheus/node_exporter_servers.yml:Z \
    $DATADIR \
    -p $PROMETHEUS_PORT:9090 \
    --name $PROMETHEUS_NAME prom/prometheus:$PROMETHEUS_VERSION \

if [ $? -ne 0 ]; then
    echo "Error: Prometheus container failed to start"
    exit 1
fi
if [ "$VERSIONS" = "latest" ]; then
	VERSIONS=$LATEST
else
	if [ "$VERSIONS" = "all" ]; then
		VERSIONS=$ALL
	fi
fi

# Number of retries waiting for a Docker container to start
RETRIES=7

# Wait till Prometheus is available
printf "Wait for Prometheus container to start."
TRIES=0
until $(curl --output /dev/null -f --silent http://localhost:$PROMETHEUS_PORT) || [ $TRIES -eq $RETRIES ]; do
    printf '.'
    ((TRIES=TRIES+1))
    sleep 5
done

if [ ! "$(sudo docker ps -q -f name=$PROMETHEUS_NAME)" ]
then
        echo "Error: Prometheus container failed to start"
        exit 1
fi

sudo docker run -d -i -p $GRAFANA_PORT:3000 \
     -e "GF_AUTH_BASIC_ENABLED=false" \
     -e "GF_AUTH_ANONYMOUS_ENABLED=true" \
     -e "GF_AUTH_ANONYMOUS_ORG_ROLE=Admin" \
     -e "GF_INSTALL_PLUGINS=grafana-piechart-panel" \
     --name $GRAFANA_NAME grafana/grafana:$GRAFANA_VERSION

if [ $? -ne 0 ]; then
    echo "Error: Grafana container failed to start"
    exit 1
fi

# Wait till Grafana API is available
printf "Wait for Grafana container to start."
TRIES=0
until $(curl --output /dev/null -f --silent http://localhost:$GRAFANA_PORT/api/org) || [ $TRIES -eq $RETRIES ] ; do
    printf '.'
    ((TRIES=TRIES+1))
    sleep 5
done

if [ ! "$(sudo docker ps -q -f name=$GRAFANA_NAME)" ]
then
        echo "Error: Grafana container failed to start"
        exit 1
fi

# Can't use localhost here, because the monitoring may be running remotely.
# Also note that the port to which we need to connect is 9090, regardless of which port we bind to at localhost.
DB_ADDRESS="$(sudo docker inspect --format '{{ .NetworkSettings.IPAddress }}' $PROMETHEUS_NAME):9090"

curl -XPOST -i http://localhost:$GRAFANA_PORT/api/datasources \
     --data-binary '{"name":"prometheus", "type":"prometheus", "url":"'"http://$DB_ADDRESS"'", "access":"proxy", "basicAuth":false}' \
     -H "Content-Type: application/json"
IFS=',' ;for v in $VERSIONS; do
	curl -XPOST -i http://localhost:$GRAFANA_PORT/api/dashboards/db --data-binary @./grafana/scylla-dash.$v.json -H "Content-Type: application/json"
	curl -XPOST -i http://localhost:$GRAFANA_PORT/api/dashboards/db --data-binary @./grafana/scylla-dash-per-server.$v.json -H "Content-Type: application/json"
	curl -XPOST -i http://localhost:$GRAFANA_PORT/api/dashboards/db --data-binary @./grafana/scylla-dash-io-per-server.$v.json -H "Content-Type: application/json"
done
