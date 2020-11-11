#!/usr/bin/env bash

usage="$(basename "$0") [-h] [-g grafana port ] [ -p prometheus port ] [-m alertmanager port] -- kills existing Grafana and Prometheus Docker instances at given ports"
GRAFANA_PORT=""
PROMETHEUS_PORT=""
ALERTMANAGER_PORT=""
PROMETHEUS_NAME="aprom"
while getopts ':hg:p:m:' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    g) GRAFANA_PORT="-p $OPTARG"
       ;;
    p) PROMETHEUS_PORT="-p $OPTARG"
       PROMETHEUS_NAME="aprom-$OPTARG"
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

docker exec $PROMETHEUS_NAME kill 1
TRIES=0
OK=0
until [ $OK -eq 1 ] || [ $TRIES -eq 120 ]; do
    if VAL=`docker logs aprom|&tail -1 |grep 'See you next time'`; then
        if [ -z "$VAL" ]; then
            printf '.'
            ((TRIES=TRIES+1))
            sleep 1
        else
           OK=1
        fi
    else
        OK=1
    fi
done
sleep 2
./kill-container.sh $PROMETHEUS_PORT -b aprom
./kill-container.sh $GRAFANA_PORT -b agraf
./kill-container.sh $ALERTMANAGER_PORT -b aalert
./kill-container.sh -b agrafrender
./kill-container.sh -b loki
./kill-container.sh -b promtail



