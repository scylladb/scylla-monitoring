#!/usr/bin/env bash
usage="$(basename "$0") [-h] [-m alert_manager address]  [-L] [-T additional-prometheus-targets] [--compose] -- Generate grafna's datasource file"
CONSUL_ADDRESS=""
COMPOSE=0
BASE_DIR="$PWD/prometheus/build"
if [ -f  env.sh ]; then
    . env.sh
fi

if [ "$1" = "" ]; then
    echo "$usage"
    exit
fi
for arg; do
    shift
    if [ -z "$PARAM" ]; then
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
            (--scrap)
                PARAM="scrap"
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
    else
        DOCR=`echo $arg|cut -d',' -f1`
        VALUE=`echo $arg|cut -d',' -f2-|sed 's/#/ /g'`
        NOSPACE=`echo $arg|sed 's/ /#/g'`
        if [[ $NOSPACE == --* ]]; then
            echo "Error: No value given to --$PARAM"
            echo
            usage
            exit 1
        fi
        if [ "$PARAM" = "scrap" ]; then
            SCRAP_INTERVAL="$NOSPACE"
        fi
        unset PARAM
    fi
done

while getopts ':hL:m:T:E:s:' option; do
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
    s) BASE_DIR="$PWD/prometheus/build/stack/$OPTARG"
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

mkdir -p $BASE_DIR/
if [ -z $CONSUL_ADDRESS ]; then
    sed "s/AM_ADDRESS/$AM_ADDRESS/" $PWD/prometheus/prometheus.yml.template > $BASE_DIR/prometheus.yml
else
    if [[ ! $CONSUL_ADDRESS = *":"* ]]; then
        CONSUL_ADDRESS="$CONSUL_ADDRESS:5090"
    fi
    sed "s/AM_ADDRESS/$AM_ADDRESS/" $PWD/prometheus/prometheus.consul.yml.template| sed "s/MANAGER_ADDRESS/$CONSUL_ADDRESS/" > $BASE_DIR/prometheus.yml
fi

if [[ "$EVALUATION_INTERVAL" != "" ]]; then
    sed -i "s/  evaluation_interval: [[:digit:]]*.*/  evaluation_interval: ${EVALUATION_INTERVAL}/g" $BASE_DIR/prometheus.yml
fi
if [[ "$SCRAP_INTERVAL" != "" ]]; then
    sed -i "s/  scrape_interval: [[:digit:]]*.*# *Default.*/  scrape_interval: ${SCRAP_INTERVAL}s/g" $BASE_DIR/prometheus.yml
    TIMEOUT=$(($SCRAP_INTERVAL - 5))
    sed -i "s/  scrape_timeout: [[:digit:]]*.*# *Default.*/  scrape_timeout: ${TIMEOUT}s/g" $BASE_DIR/prometheus.yml
fi
if [ "$NO_CAS" = "1" ] && [ "$NO_CDC" = "1" ]; then
    sed -i "s/ *# FILTER_METRICS.*/    - source_labels: [__name__]\\n      regex: '(.*_cdc_.*|.*_cas.*)'\\n      action: drop/g" $BASE_DIR/prometheus.yml
elif [ "$NO_CAS" = "1" ]; then
    sed -i "s/ *# FILTER_METRICS.*/    - source_labels: [__name__]\\n      regex: '(.*_cas.*)'\\n      action: drop/g" $BASE_DIR/prometheus.yml
elif [ "$NO_CDC" = "1" ]; then
    sed -i "s/ *# FILTER_METRICS.*/    - source_labels: [__name__]\\n      regex: '(.*_cdc_.*)'\\n      action: drop/g" $BASE_DIR/prometheus.yml
fi
if [ "$NO_NODE_EXPORTER_FILE" = "1" ]; then
    sed -i "s/ *# NODE_EXPORTER_PORT_MAPPING.*/    - source_labels: [__address__]\\n      regex:  '(.*):\\\\d+'\\n      target_label: __address__\\n      replacement: '\$\{1\}'\\n/g" $BASE_DIR/prometheus.yml
fi
if [ "$NO_MANAGER_AGENT_FILE" = "1" ]; then
    sed -i "s/ *# MANAGER_AGENT_PORT_MAPPING.*/    - source_labels: [__address__]\\n      regex:  '(.*):\\\\d+'\\n      target_label: __address__\\n      replacement: \'\$\{1\}\'\\n/g" $BASE_DIR/prometheus.yml
fi

for val in "${PROMETHEUS_TARGETS[@]}"; do
    if [[ ! -f $val ]]; then
        echo "Target file $val does not exists"
        exit 1
    fi
    cat $val >> $BASE_DIR/prometheus.yml
done
