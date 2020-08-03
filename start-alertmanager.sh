#!/usr/bin/env bash

if [ "$1" = "-e" ]; then
. enterprise_versions.sh
else
. versions.sh
fi
is_podman="$(docker --help | grep -o podman)"
VERSIONS=$DEFAULT_VERSION
RULE_FILE=$PWD/prometheus/rule_config.yml
ALERT_MANAGER_VERSION="v0.20.0"
DOCKER_PARAM=""
BIND_ADDRESS=""
ALERTMANAGER_COMMANDS=""
usage="$(basename "$0") [-h] [-p alertmanager port ] [-l] [-D encapsulate docker param] [-C alertmanager commands] [-r rule-file]"

while getopts ':hlp:r:D:C:A:' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    p) ALERTMANAGER_PORT=$OPTARG
       ;;
    r) RULE_FILE=`readlink -m $OPTARG`
       ;;

    l) DOCKER_PARAM="$DOCKER_PARAM --net=host"
       ;;
    D) DOCKER_PARAM="$DOCKER_PARAM $OPTARG"
       ;;
    C) ALERTMANAGER_COMMANDS="$ALERTMANAGER_COMMANDS $OPTARG"
       ;;
    A) BIND_ADDRESS="$OPTARG:"
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
if [ -z $ALERTMANAGER_PORT ]; then
    ALERTMANAGER_PORT=9093
    ALERTMANAGER_NAME=aalert
else
    ALERTMANAGER_NAME=aalert-$ALERTMANAGER_PORT
fi

docker container inspect $ALERTMANAGER_NAME > /dev/null 2>&1
if [ $? -eq 0 ]; then
    printf "\nSome of the monitoring docker instances ($ALERTMANAGER_NAME) exist. Make sure all containers are killed and removed. You can use kill-all.sh for that\n"
    exit 1
fi

if [[ ! $DOCKER_PARAM = *"--net=host"* ]]; then
    PORT_MAPPING="-p $BIND_ADDRESS$ALERTMANAGER_PORT:9093"
fi


docker run -d $DOCKER_PARAM -i $PORT_MAPPING \
	 -v $RULE_FILE:/etc/alertmanager/config.yml:z \
     --name $ALERTMANAGER_NAME prom/alertmanager:$ALERT_MANAGER_VERSION $ALERTMANAGER_COMMANDS --log.level=debug --config.file=/etc/alertmanager/config.yml >& /dev/null


if [ $? -ne 0 ]; then
    echo "Error: Alertmanager container failed to start"
    echo "For more information use: docker logs $ALERTMANAGER_NAME"
    exit 1
fi

# Wait till Alertmanager is available
RETRIES=5
TRIES=0
until $(curl --output /dev/null -f --silent http://localhost:$ALERTMANAGER_PORT) || [ $TRIES -eq $RETRIES ]; do
    ((TRIES=TRIES+1))
    sleep 5
done

if [ ! "$(docker ps -q -f name=$ALERTMANAGER_NAME)" ]
then
    echo "Error: Alertmanager container failed to start"
    exit 1
fi

AM_ADDRESS="$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' $ALERTMANAGER_NAME):9093"
if [ ! -z "$is_podman" ] && [ "$AM_ADDRESS" = ":9093" ]; then
    HOST_IP=`hostname -I | awk '{print $1}'`
    AM_ADDRESS="$HOST_IP:9093"
fi
echo $AM_ADDRESS
