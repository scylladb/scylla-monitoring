#!/usr/bin/env bash

if [ "$1" = "-e" ]; then
. enterprise_versions.sh
else
. versions.sh
fi
VERSIONS=$DEFAULT_VERSION

ALERT_MANAGER_VERSION="v0.12.0"
LOCAL=""

usage="$(basename "$0") [-h] [-p alertmanager port ] [-l]"

while getopts ':hlp:' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    p) ALERTMANAGER_PORT=$OPTARG
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

if [ -z $ALERTMANAGER_PORT ]; then
    ALERTMANAGER_PORT=9093
    ALERTMANAGER_NAME=aalert
else
    ALERTMANAGER_NAME=aalert-$ALERTMANAGER_PORT
fi

sudo docker run -d $LOCAL -i -p $ALERTMANAGER_PORT:9093 \
	-v $PWD/prometheus/rule_config.yml:/etc/alertmanager/config.yml:Z \
     --name $ALERTMANAGER_NAME prom/alertmanager:$ALERT_MANAGER_VERSION > /dev/null


if [ $? -ne 0 ]; then
    echo "Error: Alertmanager container failed to start"
    exit 1
fi

# Wait till Alertmanager is available
RETRIES=5
TRIES=0
until $(curl --output /dev/null -f --silent http://localhost:$ALERTMANAGER_PORT) || [ $TRIES -eq $RETRIES ]; do
    ((TRIES=TRIES+1))
    sleep 5
done

if [ ! "$(sudo docker ps -q -f name=$ALERTMANAGER_NAME)" ]
then
    echo "Error: Alertmanager container failed to start"
    exit 1
fi

AM_ADDRESS="$(sudo docker inspect --format '{{ .NetworkSettings.IPAddress }}' $ALERTMANAGER_NAME):$ALERTMANAGER_PORT"
echo $AM_ADDRESS