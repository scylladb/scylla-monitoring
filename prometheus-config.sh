#!/usr/bin/env bash
usage="$(basename "$0") [-h] [-m alert_manager address]  [-L] [-T additional-prometheus-targets] [--compose] -- Generate grafna's datasource file"
CONSUL_ADDRESS=""
COMPOSE=0
if [ "$1" = "" ]; then
    echo "$usage"
    exit
fi
for arg; do
    shift
    case $arg in
        (--compose) COMPOSE=1
            AM_ADDRESS="aalert:9093"
            ;;
        (*) set -- "$@" "$arg"
            ;;
    esac
done

while getopts ':hL:m:T:' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    L) CONSUL_ADDRESS="$OPTARG"
       ;;
    T) PROMETHEUS_TARGETS+=("$OPTARG")
       ;;
    m) AM_ADDRESS="$OPTARG"
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

mkdir -p $PWD/prometheus/build/
if [ -z $CONSUL_ADDRESS ]; then
    sed "s/AM_ADDRESS/$AM_ADDRESS/" $PWD/prometheus/prometheus.yml.template > $PWD/prometheus/build/prometheus.yml
else
    if [[ ! $CONSUL_ADDRESS = *":"* ]]; then
        CONSUL_ADDRESS="$CONSUL_ADDRESS:5090"
    fi
    sed "s/AM_ADDRESS/$AM_ADDRESS/" $PWD/prometheus/prometheus.consul.yml.template| sed "s/MANAGER_ADDRESS/$CONSUL_ADDRESS/" > $PWD/prometheus/build/prometheus.yml
fi

for val in "${PROMETHEUS_TARGETS[@]}"; do
    if [[ ! -f $val ]]; then
        echo "Target file $val does not exists"
        exit 1
    fi
    cat $val >> $PWD/prometheus/build/prometheus.yml
done
