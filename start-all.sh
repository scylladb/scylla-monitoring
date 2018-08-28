#!/usr/bin/env bash

echo ""
echo "*****************************************************"
echo "* WARNING: You are using the unstable master branch *"
echo "* Check the README.md file for the stable releases  *"
echo "*****************************************************"
echo ""

if [ "$1" = "-e" ]; then
. enterprise_versions.sh
else		
. versions.sh
fi
VERSIONS=$DEFAULT_VERSION
usage="$(basename "$0") [-h] [-e] [-d Prometheus data-dir] [-s scylla-target-file] [-n node-target-file] [-l] [-v comma seperated versions] [-j additional dashboard to load to Grafana, multiple params are supported] [-c grafana enviroment variable, multiple params are supported] [-b Prometheus command line options] [-g grafana port ] [ -p prometheus port ] [-a admin password] [-m alertmanager port] [ -M scylla-manager version ] [-D encapsulate docker param] -- starts Grafana and Prometheus Docker instances"
PROMETHEUS_VERSION=v2.3.2

SCYLLA_TARGET_FILE=$PWD/prometheus/scylla_servers.yml
NODE_TARGET_FILE=$PWD/prometheus/node_exporter_servers.yml
SCYLLA_MANGER_TARGET_FILE=$PWD/prometheus/scylla_manager_servers.yml
GRAFANA_ADMIN_PASSWORD=""
ALERTMANAGER_PORT=""
DOCKER_PARAM=""

while getopts ':hled:g:p:v:s:n:a:c:j:b:m:M:D:' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    v) VERSIONS=$OPTARG
       ;;
    M) MANAGER_VERSION=$OPTARG
       ;;
    d) DATA_DIR=$OPTARG
       ;;
    g) GRAFANA_PORT="-g $OPTARG"
       ;;
    m) ALERTMANAGER_PORT="-p $OPTARG"
       ;;
    p) PROMETHEUS_PORT=$OPTARG
       ;;
    s) SCYLLA_TARGET_FILE=$OPTARG
       ;;
    n) NODE_TARGET_FILE=$OPTARG
       ;;
    l) DOCKER_PARAM="$DOCKER_PARAM --net=host"
       ;;
    a) GRAFANA_ADMIN_PASSWORD="-a $OPTARG"
       ;;
    j) GRAFANA_DASHBOARD_ARRAY+=("$OPTARG")
       ;;
    c) GRAFANA_ENV_ARRAY+=("$OPTARG")
       ;;
    D) DOCKER_PARAM="$DOCKER_PARAM $OPTARG"
       ;;
    b) PROMETHEUS_COMMAND_LINE_OPTIONS_ARRAY+=("$OPTARG")
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

printf "Wait for alert manager container to start."

AM_ADDRESS=`./start-alertmanager.sh $ALERTMANAGER_PORT -D "$DOCKER_PARAM"`
if [ $? -ne 0 ]; then
    echo "$AM_ADDRESS"
    exit 1
fi
if [ -z $PROMETHEUS_PORT ]; then
    PROMETHEUS_PORT=9090
    PROMETHEUS_NAME=aprom
else
    PROMETHEUS_NAME=aprom-$PROMETHEUS_PORT
fi

docker container inspect $PROMETHEUS_NAME > /dev/null
if [ $? -eq 0 ]; then
    printf "\nSome of the monitoring docker instances ($PROMETHEUS_NAME) exist. Make sure all containers are killed and removed. You can use kill-all.sh for that\n"
    exit 1
fi


# Exit if Docker engine is not running
if [ ! "$(docker ps)" ]
then
        echo "Error: Docker engine is not running"
        exit 1
fi

for val in "${PROMETHEUS_COMMAND_LINE_OPTIONS_ARRAY[@]}"; do
    PROMETHEUS_COMMAND_LINE_OPTIONS+=" -$val"
done

mkdir -p $PWD/prometheus/build/
sed "s/AM_ADDRESS/$AM_ADDRESS/" $PWD/prometheus/prometheus.yml.template > $PWD/prometheus/build/prometheus.yml

if [ -z $DATA_DIR ]
then
    docker run -d $DOCKER_PARAM \
         -v $PWD/prometheus/build/prometheus.yml:/etc/prometheus/prometheus.yml:Z \
         -v $PWD/prometheus/prometheus.rules.yml:/etc/prometheus/prometheus.rules.yml:Z \
         -v $(readlink -m $SCYLLA_TARGET_FILE):/etc/scylla.d/prometheus/scylla_servers.yml:Z \
         -v $(readlink -m $SCYLLA_MANGER_TARGET_FILE):/etc/scylla.d/prometheus/scylla_manager_servers.yml:Z \
         -v $(readlink -m $NODE_TARGET_FILE):/etc/scylla.d/prometheus/node_exporter_servers.yml:Z \
         -p $PROMETHEUS_PORT:9090 --name $PROMETHEUS_NAME prom/prometheus:$PROMETHEUS_VERSION --config.file=/etc/prometheus/prometheus.yml $PROMETHEUS_COMMAND_LINE_OPTIONS
else
    echo "Loading prometheus data from $DATA_DIR"
    docker run -d $DOCKER_PARAM -v $DATA_DIR:/prometheus-data \
         -v $PWD/prometheus/build/prometheus.yml:/etc/prometheus/prometheus.yml:Z \
         -v $PWD/prometheus/prometheus.rules.yml:/etc/prometheus/prometheus.rules.yml:Z \
         -v $(readlink -m $SCYLLA_TARGET_FILE):/etc/scylla.d/prometheus/scylla_servers.yml:Z \
         -v $(readlink -m $SCYLLA_MANGER_TARGET_FILE):/etc/scylla.d/prometheus/scylla_manager_servers.yml:Z \
         -v $(readlink -m $NODE_TARGET_FILE):/etc/scylla.d/prometheus/node_exporter_servers.yml:Z \
         -p $PROMETHEUS_PORT:9090 --name $PROMETHEUS_NAME prom/prometheus:$PROMETHEUS_VERSION  --config.file=/etc/prometheus/prometheus.yml $PROMETHEUS_COMMAND_LINE_OPTIONS
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

if [ ! "$(docker ps -q -f name=$PROMETHEUS_NAME)" ]
then
        echo "Error: Prometheus container failed to start"
        exit 1
fi

# Can't use localhost here, because the monitoring may be running remotely.
# Also note that the port to which we need to connect is 9090, regardless of which port we bind to at localhost.
DB_ADDRESS="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $PROMETHEUS_NAME):9090"

for val in "${GRAFANA_ENV_ARRAY[@]}"; do
        GRAFANA_ENV_COMMAND="$GRAFANA_ENV_COMMAND -c $val"
done

for val in "${GRAFANA_DASHBOARD_ARRAY[@]}"; do
        GRAFANA_DASHBOARD_COMMAND="$GRAFANA_DASHBOARD_COMMAND -j $val"
done

./start-grafana.sh -p $DB_ADDRESS -D "$DOCKER_PARAM" $GRAFANA_PORT -m $AM_ADDRESS -M $MANAGER_VERSION -v $VERSIONS $GRAFANA_ENV_COMMAND $GRAFANA_DASHBOARD_COMMAND $GRAFANA_ADMIN_PASSWORD
