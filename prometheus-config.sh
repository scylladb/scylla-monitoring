#!/usr/bin/env bash
usage="$(basename "$0") [-h] [-m alert_manager address]  [-L] [-T additional-prometheus-targets] [--compose] -- Generate grafna's datasource file"
CONSUL_ADDRESS=""
COMPOSE=0
if [ -f  env.sh ]; then
    . env.sh
fi

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
        (--no-cas-cdc)
            NO_CAS="1"
            NO_CDC="1"
            ;;
        (--no-cas)
            NO_CAS="1"
            ;;
        (--no-cdc)
            NO_CDC="1"
            ;;
        (--no-node-exporter-file)
            NO_NODE_EXPORTER_FILE="1"
            ;;
        (--no-manager-agent-file)
            NO_MANAGER_AGENT_FILE="1"
            ;;
        (*) set -- "$@" "$arg"
            ;;
    esac
done

while getopts ':hL:m:T:E:' option; do
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
    E) EVALUATION_INTERVAL="$OPTARG"
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

if [[ "$EVALUATION_INTERVAL" != "" ]]; then
    sed -i "s/  evaluation_interval: [[:digit:]]*.*/  evaluation_interval: ${EVALUATION_INTERVAL}/g" $PWD/prometheus/build/prometheus.yml
fi
if [ "$NO_CAS" = "1" ] && [ "$NO_CDC" = "1" ]; then
    sed -i "s/ *# FILTER_METRICS.*/    - source_labels: [__name__]\\n      regex: '(.*_cdc_.*|.*_cas.*)'\\n      action: drop/g" $PWD/prometheus/build/prometheus.yml
elif [ "$NO_CAS" = "1" ]; then
    sed -i "s/ *# FILTER_METRICS.*/    - source_labels: [__name__]\\n      regex: '(.*_cas.*)'\\n      action: drop/g" $PWD/prometheus/build/prometheus.yml
elif [ "$NO_CDC" = "1" ]; then
    sed -i "s/ *# FILTER_METRICS.*/    - source_labels: [__name__]\\n      regex: '(.*_cdc_.*)'\\n      action: drop/g" $PWD/prometheus/build/prometheus.yml
fi
if [ "$NO_NODE_EXPORTER_FILE" = "1" ]; then
    sed -i "s/ *# NODE_EXPORTER_PORT_MAPPING.*/    - source_labels: [__address__]\\n      regex:  '(.*):\\\\d+'\\n      target_label: __address__\\n      replacement: '\$\{1\}'\\n/g" $PWD/prometheus/build/prometheus.yml
fi
if [ "$NO_MANAGER_AGENT_FILE" = "1" ]; then
    sed -i "s/ *# MANAGER_AGENT_PORT_MAPPING.*/    - source_labels: [__address__]\\n      regex:  '(.*):\\\\d+'\\n      target_label: __address__\\n      replacement: \'\$\{1\}\'\\n/g" $PWD/prometheus/build/prometheus.yml
fi

for val in "${PROMETHEUS_TARGETS[@]}"; do
    if [[ ! -f $val ]]; then
        echo "Target file $val does not exists"
        exit 1
    fi
    cat $val >> $PWD/prometheus/build/prometheus.yml
done
