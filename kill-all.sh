#!/usr/bin/env bash

usage="$(basename "$0") [-h] [-g grafana port ] [ -p prometheus port ] [-m alertmanager port] -- kills existing Grafana and Prometheus Docker instances at given ports"
GRAFANA_PORT=""
PROMETHEUS_PORT=""
ALERTMANAGER_PORT=""
while getopts ':hg:p:m:' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    g) GRAFANA_PORT="-p $OPTARG"
       ;;
    p) PROMETHEUS_PORT="-p $OPTARG"
       ;;
    m) ALERTMANAGER_PORT="-p $OPTARG"
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

./kill-container.sh $PROMETHEUS_PORT -b aprom
./kill-container.sh $GRAFANA_PORT -b agraf
./kill-container.sh $ALERTMANAGER_PORT -b aalert



