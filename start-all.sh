#!/usr/bin/env bash

usage="$(basename "$0") [-h] [-d Prometheus data-dir] -- starts Grafana and Prometheus Docker instances"

while getopts ':hd:' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    d) DATA_DIR=$OPTARG
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

# Exit if Docker engine is not running
if [ ! "$(sudo docker ps)" ]
then
        echo "Error: Docker engine is not running"
        exit 1
fi

if [ -z $DATA_DIR ]
then
    sudo docker run -d -v $PWD/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:Z -p 9090:9090 --name aprom prom/prometheus:v1.0.0
else
    echo "Loading prometheus data from $DATA_DIR"
    sudo docker run -d -v $DATA_DIR:/prometheus:Z -v $PWD/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:Z -p 9090:9090 --name aprom prom/prometheus:v1.0.0
fi

if [ $? -ne 0 ]; then
    echo "Error: Prometheus container failed to start"
    exit 1
fi

# Number of retries waiting for a Docker container to start
RETRIES=7

# Wait till Prometheus is available
printf "Wait for Prometheus container to start."
TRIES=0
until $(curl --output /dev/null -f --silent http://localhost:9090) || [ $TRIES -eq $RETRIES ]; do
    printf '.'
    ((TRIES=TRIES+1))
    sleep 5
done

if [ ! "$(sudo docker ps -q -f name=aprom)" ]
then
        echo "Error: Prometheus container failed to start"
        exit 1
fi

sudo docker run -d -v $PWD/grafana/dashboards:/var/lib/grafana/dashboards:Z -i -p 3000:3000 \
     -e "GF_AUTH_BASIC_ENABLED=false" \
     -e "GF_AUTH_ANONYMOUS_ENABLED=true" \
     -e "GF_AUTH_ANONYMOUS_ORG_ROLE=Admin" \
     -e "GF_INSTALL_PLUGINS=grafana-piechart-panel" \
     -e "GF_DASHBOARDS_JSON_ENABLED=TRUE" \
     -e "GF_DASHBOARDS_JSON_PATH=/var/lib/grafana/dashboards" \
     --name agraf grafana/grafana:3.1.0

if [ $? -ne 0 ]; then
    echo "Error: Grafana container failed to start"
    exit 1
fi

# Wait till Grafana API is available
printf "Wait for Grafana container to start."
TRIES=0
until $(curl --output /dev/null -f --silent http://localhost:3000/api/org) || [ $TRIES -eq $RETRIES ] ; do
    printf '.'
    ((TRIES=TRIES+1))
    sleep 5
done

if [ ! "$(sudo docker ps -q -f name=agraf)" ]
then
        echo "Error: Grafana container failed to start"
        exit 1
fi

DB_IP="$(sudo docker inspect --format '{{ .NetworkSettings.IPAddress }}' aprom)"

curl -XPOST -i http://localhost:3000/api/datasources \
     --data-binary '{"name":"prometheus", "type":"prometheus", "url":"'"http://$DB_IP:9090"'", "access":"proxy", "basicAuth":false}' \
     -H "Content-Type: application/json"
