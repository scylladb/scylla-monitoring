#!/usr/bin/env bash

if [ "$1" = "-e" ]; then
. enterprise_versions.sh
else		
. versions.sh
fi
VERSIONS=$DEFAULT_VERSION
usage="$(basename "$0") [-h] [-e] [-d Prometheus data-dir] [-s scylla-target-file] [-n node-target-file] [-l] [-v comma seperated versions] [-g grafana port ] [ -p prometheus port ] -- starts Grafana and Prometheus Docker instances"

GRAFANA_VERSION=4.1.1
PROMETHEUS_VERSION=v1.5.2
LOCAL=""

SCYLLA_TARGET_FILE=$PWD/prometheus/scylla_servers.yml
NODE_TARGET_FILE=$PWD/prometheus/node_exporter_servers.yml

while getopts ':hled:g:p:v:s:n:' option; do
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
    s) SCYLLA_TARGET_FILE=$OPTARG
       ;;
    n) NODE_TARGET_FILE=$OPTARG
       ;;
    l) LOCAL="--net=host"
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

# Exit if Docker engine is not running
if [ ! "$(sudo docker ps)" ]
then
        echo "Error: Docker engine is not running"
        exit 1
fi

if [ -z $DATA_DIR ]
then
    sudo docker run -d $LOCAL \
         -v $PWD/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:Z \
         -v $(readlink -m $SCYLLA_TARGET_FILE):/etc/prometheus/scylla_servers.yml:Z \
         -v $(readlink -m $NODE_TARGET_FILE):/etc/prometheus/node_exporter_servers.yml:Z \
         -p $PROMETHEUS_PORT:9090 --name $PROMETHEUS_NAME prom/prometheus:$PROMETHEUS_VERSION
else
    echo "Loading prometheus data from $DATA_DIR"
    sudo docker run -d $LOCAL -v $DATA_DIR:/prometheus:Z \
         -v $PWD/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:Z \
         -v $(readlink -m $SCYLLA_TARGET_FILE):/etc/prometheus/scylla_servers.yml:Z \
         -v $(readlink -m $NODE_TARGET_FILE):/etc/prometheus/node_exporter_servers.yml:Z \
         -p $PROMETHEUS_PORT:9090 --name $PROMETHEUS_NAME prom/prometheus:$PROMETHEUS_VERSION
fi

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

sudo docker run -d $LOCAL -i -p $GRAFANA_PORT:3000 \
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

./load-grafana.sh -p $DB_ADDRESS -g $GRAFANA_PORT -v $VERSIONS
