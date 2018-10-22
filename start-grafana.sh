#!/usr/bin/env bash

if [ "$1" = "-e" ]; then
. enterprise_versions.sh
else
. versions.sh
fi
VERSIONS=$DEFAULT_VERSION

GRAFANA_VERSION=5.4.2
DB_ADDRESS="127.0.0.1:9090"
LOCAL=""
GRAFANA_ADMIN_PASSWORD="admin"
GRAFANA_AUTH=false
GRAFANA_AUTH_ANONYMOUS=true
AM_ADDRESS=""
DOCKER_PARAM=""

usage="$(basename "$0") [-h] [-v comma separated versions ] [-g grafana port ] [-n grafana container name ] [-p ip:port address of prometheus ] [-j additional dashboard to load to Grafana, multiple params are supported] [-c grafana enviroment variable, multiple params are supported] [-x http_proxy_host:port] [-m alert_manager address] [-a admin password] [ -M scylla-manager version ] [-D encapsulate docker param] -- loads the prometheus datasource and the Scylla dashboards into an existing grafana installation"

while getopts ':hlg:n:p:v:a:x:c:j:m:M:D:' option; do
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
       ALERT_MANAGER_ADDRESS=$OPTARG
       ;;
    l) DOCKER_PARAM="$DOCKER_PARAM --net=host"
       ;;
    D) DOCKER_PARAM="$DOCKER_PARAM $OPTARG"
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

docker container inspect $GRAFANA_NAME > /dev/null 2>&1
if [ $? -eq 0 ]; then
    printf "\nSome of the monitoring docker instances ($GRAFANA_NAME) exist. Make sure all containers are killed and removed. You can use kill-all.sh for that\n"
    exit 1
fi

proxy_args=()
if [[ -n "$HTTP_PROXY" ]]; then
    proxy_args=(-e http_proxy="$HTTP_PROXY")
fi

for val in "${GRAFANA_ENV_ARRAY[@]}"; do
        GRAFANA_ENV_COMMAND="$GRAFANA_ENV_COMMAND -e $val"
done


for val in "${GRAFANA_DASHBOARD_ARRAY[@]}"; do
        GRAFANA_DASHBOARD_COMMAND="$GRAFANA_DASHBOARD_COMMAND -j $val"
done

./generate-dashboards.sh -v $VERSIONS -M $MANAGER_VERSION $GRAFANA_DASHBOARD_COMMAND
mkdir -p grafana/provisioning/datasources
sed "s/DB_ADDRESS/$DB_ADDRESS/" grafana/datasource.yml | sed "s/AM_ADDRESS/$ALERT_MANAGER_ADDRESS/" > grafana/provisioning/datasources/datasource.yaml

docker run -d $DOCKER_PARAM -i -u $UID -p $GRAFANA_PORT:3000 \
     -e "GF_AUTH_BASIC_ENABLED=$GRAFANA_AUTH" \
     -e "GF_AUTH_ANONYMOUS_ENABLED=$GRAFANA_AUTH_ANONYMOUS" \
     -e "GF_AUTH_ANONYMOUS_ORG_ROLE=Admin" \
     -v $PWD/grafana/build:/var/lib/grafana/dashboards \
     -v $PWD/grafana/plugins:/var/lib/grafana/plugins \
     -v $PWD/grafana/provisioning:/var/lib/grafana/provisioning \
     -e "GF_PATHS_PROVISIONING=/var/lib/grafana/provisioning" \
     -e "GF_SECURITY_ADMIN_PASSWORD=$GRAFANA_ADMIN_PASSWORD" \
     $GRAFANA_ENV_COMMAND \
     "${proxy_args[@]}" \
     --name $GRAFANA_NAME grafana/grafana:$GRAFANA_VERSION

if [ $? -ne 0 ]; then
    echo "Error: Grafana container failed to start"
    echo "Run \`docker logs $GRAFANA_NAME --details\` for more information"
    exit 1
fi

# Wait till Grafana API is available
printf "Wait for Grafana container to start."
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
        echo "Run \`docker logs $GRAFANA_NAME --details\` for more information"
        exit 1
fi

printf "\nStart completed successfully, check http://localhost:$GRAFANA_PORT\n"
