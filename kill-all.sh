#!/usr/bin/env bash
. versions.sh
usage="$(basename "$0") [-h] [-g grafana port ] [ -p prometheus port ] [-m alertmanager port] [-w max wait time for prometheus] -- kills existing Grafana and Prometheus Docker instances at given ports"
GRAFANA_PORT=""
PROMETHEUS_PORT=""
ALERTMANAGER_PORT=""
PROMETHEUS_NAME="aprom"
PROMETHEUS_KILL_WAITTIME="120"
LOKI_PORT=""
PROMTAIL_PORT=""
for arg; do
    shift
    if [ -z "$LIMIT" ]; then
       case $arg in
            (--loki-port)
                LIMIT="1"
                PARAM="loki-port"
                ;;
            (--promtail-port)
                LIMIT="1"
                PARAM="promtail-port"
                ;;
            (--stack)
                LIMIT="1"
                PARAM="stack"
                ;;
            (*) set -- "$@" "$arg"
                ;;
        esac
    else
        DOCR=`echo $arg|cut -d',' -f1`
        VALUE=`echo $arg|cut -d',' -f2-|sed 's/#/ /g'`
        NOSPACE=`echo $arg|sed 's/ /#/g'`
        if [ "$PARAM" = "loki-port" ]; then
            LOKI_PORT="-p $NOSPACE"
            unset PARAM
        elif [ "$PARAM" = "promtail-port" ]; then
            PROMTAIL_PORT="-p $NOSPACE"
            unset PARAM
        elif [ "$PARAM" = "stack" ]; then
            STACK_ID="$NOSPACE"
            unset PARAM
        fi
        unset LIMIT
    fi
done
while getopts ':hg:p:w:m:' option; do
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
    w) PROMETHEUS_KILL_WAITTIME=$OPTARG
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

if [ "$STACK_ID" != "" ]; then
    PROMETHEUS_PORT="-p "${STACK_PROMETHEUS["$STACK_ID"]}
    GRAFANA_PORT="-p "${STACK_GRAFANA["$STACK_ID"]}
    ALERTMANAGER_PORT="-p "${STACK_ALERTMANAGER["$STACK_ID"]}
    PROMETHEUS_NAME="aprom-"${STACK_PROMETHEUS["$STACK_ID"]}
fi

docker exec $PROMETHEUS_NAME kill 15
TRIES=0
OK=0
until [ $OK -eq 1 ] || [ $TRIES -eq $PROMETHEUS_KILL_WAITTIME ]; do
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
if [ -z $STACK_ID ]; then
    ./kill-container.sh -b agrafrender
    ./kill-container.sh -b vmalert
    ./kill-container.sh $LOKI_PORT -b loki
    ./kill-container.sh $PROMTAIL_PORT -b promtail
    ./kill-container.sh -b sidecar1
    ./kill-container.sh -b thanos
    ./kill-container.sh -b datadog-agent
fi

