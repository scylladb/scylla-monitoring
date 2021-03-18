#!/usr/bin/env bash

is_podman="$(docker --help | grep -o podman)"
VERSIONS=$DEFAULT_VERSION
LOKI_RULE_DIR=$PWD/loki/rules
LOKI_CONF_DIR=$PWD/loki/conf
PROMTAIL_CONFIG=$PWD/loki/promtail/promtail_config.yml
LOKI_VERSION="2.1.0"
DOCKER_PARAM=""
BIND_ADDRESS=""
LOKI_COMMANDS=""
usage="$(basename "$0") [-h] [-l] [-D encapsulate docker param] [-m alert_manager address]"

while getopts ':hlp:D:m:A:' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    p) LOKI_PORT=$OPTARG
       ;;
    r) LOKI_RULE_DIR=`readlink -m $OPTARG`
       ;;
    l) DOCKER_PARAM="$DOCKER_PARAM --net=host"
       ;;
    D) DOCKER_PARAM="$DOCKER_PARAM $OPTARG"
       ;;
    C) LOKI_COMMANDS="$LOKI_COMMANDS $OPTARG"
       ;;
    A) BIND_ADDRESS="$OPTARG:"
       ;;
    m) ALERT_MANAGER_ADDRESS=$OPTARG
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
if [ -z $LOKI_PORT ]; then
    LOKI_PORT=3100
    LOKI_NAME=loki
else
    LOKI_NAME=loki-$LOKI_PORT
fi

docker container inspect $LOKI_NAME > /dev/null 2>&1
if [ $? -eq 0 ]; then
    printf "\nSome of the monitoring docker instances ($LOKI_NAME) exist. Make sure all containers are killed and removed. You can use kill-all.sh for that\n"
    exit 1
fi

if [[ ! $DOCKER_PARAM = *"--net=host"* ]]; then
    PORT_MAPPING="-p $BIND_ADDRESS$LOKI_PORT:3100"
fi

if [ -z $ALERT_MANAGER_ADDRESS ]; then
	ALERT_MANAGER_ADDRESS="$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' aalert):9093"
fi

sed "s/ALERTMANAGER/$ALERT_MANAGER_ADDRESS/" loki/conf/loki-config.template.yaml > loki/conf/loki-config.yaml

docker run -d $DOCKER_PARAM -i $PORT_MAPPING \
	 -v $LOKI_RULE_DIR:/etc/loki/rules:z \
	 -v $LOKI_CONF_DIR:/mnt/config:z \
     --name $LOKI_NAME grafana/loki:$LOKI_VERSION $LOKI_COMMANDS --config.file=/mnt/config/loki-config.yaml >& /dev/null

if [ $? -ne 0 ]; then
    echo "Error: Loki container failed to start"
    echo "For more information use: docker logs $LOKI_NAME"
    exit 1
fi

# Wait till Loki is available
RETRIES=5
TRIES=0
until $(curl --output /dev/null -f --silent http://localhost:$LOKI_PORT) || [ $TRIES -eq $RETRIES ]; do
    ((TRIES=TRIES+1))
    sleep 5
done

if [ ! "$(docker ps -q -f name=$LOKI_NAME)" ]
then
    echo "Error: Loki container failed to start"
    exit 1
fi

LOKI_ADDRESS="$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' $LOKI_NAME):3100"
if [ ! -z "$is_podman" ] && [ "$AM_ADDRESS" = ":3100" ]; then
    HOST_IP=`hostname -I | awk '{print $1}'`
    LOKI_ADDRESS="$HOST_IP:3100"
fi

if [ -z $PROMTAIL_PORT ]; then
    PROMTAIL_PORT=9080
    PROMTAIL_NAME=promtail
else
    PROMTAIL_NAME=promtail-$PROMTAIL_PORT
fi

docker container inspect $PROMTAIL_NAME > /dev/null 2>&1
if [ $? -eq 0 ]; then
    printf "\nSome of the monitoring docker instances ($PROMTAIL_NAME) exist. Make sure all containers are killed and removed. You can use kill-all.sh for that\n"
    exit 1
fi

if [[ ! $DOCKER_PARAM = *"--net=host"* ]]; then
    PROMTAIL_PORT_MAPPING="-p $BIND_ADDRESS$PROMTAIL_PORT:9080 -p ${BIND_ADDRESS}1514:1514"
fi

sed "s/LOKI_IP/$LOKI_ADDRESS/" loki/promtail/promtail_config.template.yml > loki/promtail/promtail_config.yml

docker run -d $DOCKER_PARAM -i $PROMTAIL_PORT_MAPPING \
	 -v $PROMTAIL_CONFIG:/etc/promtail/config.yml:z \
     --name $PROMTAIL_NAME grafana/promtail:$LOKI_VERSION --config.file=/etc/promtail/config.yml >& /dev/null

if [ $? -ne 0 ]; then
    echo "Error: Promtail container failed to start"
    echo "For more information use: docker logs $PROMTAIL_NAME"
    exit 1
fi

# Wait till Loki is available
RETRIES=5
TRIES=0
until $(curl --output /dev/null -f --silent http://localhost:$PROMTAIL_PORT) || [ $TRIES -eq $RETRIES ]; do
    ((TRIES=TRIES+1))
    sleep 5
done

if [ ! "$(docker ps -q -f name=$PROMTAIL_NAME)" ]
then
    echo "Error: Promtail container failed to start"
    exit 1
fi

echo "$LOKI_ADDRESS"
