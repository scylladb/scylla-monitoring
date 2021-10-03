#!/usr/bin/env bash

. versions.sh
PROM_ADRESS=`docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' aprom`:9090
DATADIR="/prometheus-data/"
NAME="1"
if [ "`id -u`" -eq 0 ]; then
    echo "Running as root is not advised, please check the documentation on how to run as non-root user"
else
    GROUPID=`id -g`
    USER_PERMISSIONS="-u $UID:$GROUPID"
fi
function usage {
  __usage="Usage: $(basename $0) [-h] [-d /path/to/dir] [-a ip:port] [-A ip]

Options:
  -h print this help and exit
  -d path/to/Prometheus/data/dir - Prometheus  external data directory, must be used
  -a prometheus address          - Prometheus address:port
  -A address                     - bind to a specific ip address

The script starts Thanos sidecart, it will read from Prometheus directory, so that directory must be external
"
  echo "$__usage"
}

group_args=()
is_podman="$(docker --help | grep -o podman)"
if [ ! -z "$is_podman" ]; then
    group_args+=(--userns=keep-id)
fi
LIMITS=""
for arg; do
    shift
    if [ -z "$LIMIT" ]; then
        case $arg in
            (--limit)
                LIMIT="1"
                ;;
            (*) set -- "$@" "$arg"
                ;;
        esac
    else
        DOCR=`echo $arg|cut -d',' -f1`
        VALUE=`echo $arg|cut -d',' -f2-|sed 's/#/ /g'`
        NOSPACE=`echo $arg|sed 's/ /#/g'`
        if [ -z ${DOCKER_LIMITS[$DOCR]} ]; then
            DOCKER_LIMITS[$DOCR]=""
        fi
        DOCKER_LIMITS[$DOCR]="${DOCKER_LIMITS[$DOCR]} $VALUE"
        LIMITS="$LIMITS --limit $NOSPACE"
        unset LIMIT
    fi
done
while getopts ':hl:p:a:d:A:n:' option; do
  case "$option" in
    l) DOCKER_PARAM="$DOCKER_PARAM --net=host"
       ;;
    d) DATA_DIR="$OPTARG"
       ;;
    h) usage
       exit
       ;;
    n) NAME="$OPTARG"
       ;;
    a) PROM_ADRESS=$OPTARG
	   ;;
	p) THANOS_SC_PORT=$OPTARG
       ;;
    A) BIND_ADDRESS="$OPTARG:"
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

if [ -z $DATA_DIR ]
then
    exit 0
else
    DATA_DIR="-v "$(readlink -m $DATA_DIR)":/data/prom$NAME:z"
fi
if [[ $DOCKER_PARAM = *"--net=host"* ]]; then
    if [ ! -z "$ALERTMANAGER_PORT" ] || [ ! -z "$GRAFANA_PORT" ] || [ ! -z $PROMETHEUS_PORT ]; then
        echo "Port mapping is not supported with host network, remove the -l flag from the command line"
        exit 1
    fi
    HOST_NETWORK=1
fi
if [ -z "$BIND_ADDRESS" ]; then
  BIND_ADDRESS=""
fi
if [ -z "$THANOS_SC_PORT"]; then
    THANOS_SC_PORT="10911"
fi

if [ -z $HOST_NETWORK ]; then
    PORT_MAPPING="-p $BIND_ADDRESS$THANOS_SC_PORT:10911"
fi

echo "Starting Thanos sidecar"
docker run ${DOCKER_LIMITS["sidecar"]} -d $DOCKER_PARAM $USER_PERMISSIONS \
     $DATA_DIR \
     -i $PORT_MAPPING --name sidecar$NAME thanosio/thanos:$THANOS_VERSION \
        "sidecar" \
       "--debug.name=sidecar-$NAME" \
       "--log.level=debug" \
       "--grpc-address=0.0.0.0:10911" \
       "--grpc-grace-period=1s" \
       "--http-address=0.0.0.0:10912" \
       "--http-grace-period=1s" \
       "--prometheus.url=http://$PROM_ADRESS" \
       "--tsdb.path=/data/prom$NAME" \

