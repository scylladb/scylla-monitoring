#!/usr/bin/env bash

usage="$(basename "$0") [-h] [-g grafana port ] [ -p prometheus port ] -- kills existing Grafana and Prometheus Docker instances at given ports"

while getopts ':hg:p:' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    g) GRAFANA_PORT=$OPTARG
       ;;
    p) PROMETHEUS_PORT=$OPTARG
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
if [ -z $PROMETHEUS_PORT ]; then
    PROMETHEUS_NAME=aprom
else
    PROMETHEUS_NAME=aprom-$PROMETHEUS_PORT
fi
PROMETHEUS_FILE="$PWD/prometheus/prometheus-$PROMETHEUS_PORT.yml"

sudo docker kill $GRAFANA_NAME $PROMETHEUS_NAME
sudo docker rm $GRAFANA_NAME $PROMETHEUS_NAME
rm $PROMETHEUS_FILE 2>/dev/null
