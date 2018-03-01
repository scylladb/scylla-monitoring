#!/usr/bin/env bash

if [ "$1" = "-e" ]; then
. enterprise_versions.sh
else
. versions.sh
fi
VERSIONS=$DEFAULT_VERSION

GRAFANA_VERSION=4.6.3
DB_ADDRESS="127.0.0.1:9090"
LOCAL=""
GRAFANA_ADMIN_PASSWORD="admin"
GRAFANA_AUTH=false
GRAFANA_AUTH_ANONYMOUS=true
AM_ADDRESS=""

usage="$(basename "$0") [-h] [-v comma separated versions ] [-g grafana port ] [-n grafana container name ] [-p ip:port address of prometheus ] [-j additional dashboard to load to Grafana, multiple params are supported] [-c grafana enviroment variable, multiple params are supported] [-x http_proxy_host:port] [-m alert_manager address] [-a admin password] [ -M scylla-manager version ] -- loads the prometheus datasource and the Scylla dashboards into an existing grafana installation"

while getopts ':hlg:n:p:v:a:x:c:j:m:M:' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    v) VERSIONS=$OPTARG
       ;;
    M) MANAGER_VERSION=$OPTARG
       ;;
    g) GRAFANA_PORT=$OPTARG
       ;;
    n) GRAFANA_NAME=$OPTARG
       ;;
    p) DB_ADDRESS=$OPTARG
       ;;
    m) AM_ADDRESS="-m $OPTARG"
       ;;
    l) LOCAL="--net=host"
       ;;
    a) GRAFANA_ADMIN_PASSWORD=$OPTARG
       GRAFANA_AUTH=true
       GRAFANA_AUTH_ANONYMOUS=false
       ;;
    x) HTTP_PROXY="$OPTARG"
       ;;
    c) GRAFANA_ENV_ARRAY+=("$OPTARG")
       ;;
    j) GRAFANA_DASHBOARD_ARRAY+=("$OPTARG")
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
    if [ -z $GRAFANA_NAME ]; then
        GRAFANA_NAME=agraf
    fi
fi

if [ -z $GRAFANA_NAME ]; then
    GRAFANA_NAME=agraf-$GRAFANA_PORT
fi

proxy_args=()
if [[ -n "$HTTP_PROXY" ]]; then
    proxy_args=(-e http_proxy="$HTTP_PROXY")
fi

for val in "${GRAFANA_ENV_ARRAY[@]}"; do
        GRAFANA_ENV_COMMAND="$GRAFANA_ENV_COMMAND -e $val"
done

docker run -d $LOCAL -i -p $GRAFANA_PORT:3000 \
     -e "GF_AUTH_BASIC_ENABLED=$GRAFANA_AUTH" \
     -e "GF_AUTH_ANONYMOUS_ENABLED=$GRAFANA_AUTH_ANONYMOUS" \
     -e "GF_AUTH_ANONYMOUS_ORG_ROLE=Admin" \
     -e "GF_INSTALL_PLUGINS=grafana-piechart-panel,camptocamp-prometheus-alertmanager-datasource" \
     -e "GF_SECURITY_ADMIN_PASSWORD=$GRAFANA_ADMIN_PASSWORD" \
     $GRAFANA_ENV_COMMAND \
     "${proxy_args[@]}" \
     --name $GRAFANA_NAME grafana/grafana:$GRAFANA_VERSION

if [ $? -ne 0 ]; then
    echo "Error: Grafana container failed to start"
    exit 1
fi

# Wait till Grafana API is available
printf "Waiting for Grafana container to start."
RETRIES=7
TRIES=0
until $(curl --output /dev/null -f --silent http://localhost:$GRAFANA_PORT/api/org) || [ $TRIES -eq $RETRIES ]; do
    printf '.'
    ((TRIES=TRIES+1))
    sleep 5
done

if [ ! "$(docker ps -q -f name=$GRAFANA_NAME)" ]
then
        echo "Error: Grafana container failed to start"
        exit 1
fi

for val in "${GRAFANA_DASHBOARD_ARRAY[@]}"; do
        GRAFANA_DASHBOARD_COMMAND="$GRAFANA_DASHBOARD_COMMAND -j $val"
done
./load-grafana.sh -p $DB_ADDRESS $AM_ADDRESS -g $GRAFANA_PORT -v $VERSIONS -M $MANAGER_VERSION -a $GRAFANA_ADMIN_PASSWORD $GRAFANA_DASHBOARD_COMMAND

