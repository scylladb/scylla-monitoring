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
     --name $ALERTMANAGER_NAME prom/alertmanager:$ALERT_MANAGER_VERSION

if [ $? -ne 0 ]; then
    echo "Error: Alertmanager container failed to start"
    exit 1
fi
