#!/usr/bin/env bash

VERSION="2.0.0"
DOCKER_PARAM=""
GRAFANA_NAME="agrafrender"
BIND_ADDRESS=""
GRAFANA_RENDPORT="8081"

usage="$(basename "$0") [-h] [-D encapsulate docker param] -- Start the grafana render container"

while getopts ':hlg:D:' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    l) DOCKER_PARAM="$DOCKER_PARAM --net=host"
       ;;
    D) DOCKER_PARAM="$DOCKER_PARAM $OPTARG"
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

if [ "`id -u`" -ne 0 ]; then
    GROUPID=`id -g`
    USER_PERMISSIONS="-u $UID:$GROUPID"
fi

if [[ ! $DOCKER_PARAM = *"--net=host"* ]]; then
    PORT_MAPPING="-p $GRAFANA_RENDPORT:8081"
fi

docker run -d $DOCKER_PARAM -i $USER_PERMISSIONS $PORT_MAPPING \
     --name $GRAFANA_NAME grafana/grafana-image-renderer:$VERSION
