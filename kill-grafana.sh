#!/usr/bin/env bash

usage="$(basename "$0") [-h] [-g grafana port ] -- kills existing Grafana Docker instances at given ports"

while getopts ':hg:' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    g) GRAFANA_PORT=$OPTARG
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
    GRAFANA_NAME=agraf
else
    GRAFANA_NAME=agraf-$GRAFANA_PORT
fi

sudo docker kill $GRAFANA_NAME
sudo docker rm -v $GRAFANA_NAME
