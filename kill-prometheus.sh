#!/usr/bin/env bash

usage="$(basename "$0") [-h] [ -p prometheus port ] -- kills existing Prometheus Docker instances at given ports"

while getopts ':hp:' option; do
  case "$option" in
    h) echo "$usage"
       exit
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

if [ -z $PROMETHEUS_PORT ]; then
    PROMETHEUS_NAME=aprom
else
    PROMETHEUS_NAME=aprom-$PROMETHEUS_PORT
fi


sudo docker kill $PROMETHEUS_NAME
sudo docker rm -v $PROMETHEUS_NAME
