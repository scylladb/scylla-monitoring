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
  __usage="Usage: $(basename $0) [-h] [-d /path/to/dir] [-a ip:port]

Options:
  -h print this help and exit
  -d path/to/Prometheus/data/dir - Prometheus  external data directory, must be used
  -a prometheus address          - Prometheus address:port

The script starts Thanos sidecart, it will read from Prometheus directory, so that directory must be external 
"
  echo "$__usage"
}

group_args=()
is_podman="$(docker --help | grep -o podman)"
if [ ! -z "$is_podman" ]; then
    group_args+=(--userns=keep-id)
fi

while getopts ':hl:p:a:d:n:' option; do
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
echo "Starting Thanos sidecar"
docker run -d $DOCKER_PARAM $USER_PERMISSIONS \
     $DATA_DIR \
     -i --name sidecar$NAME thanosio/thanos:$THANOS_VERSION \
        "sidecar" \
       "--debug.name=sidecar-$NAME" \
       "--log.level=debug" \
       "--grpc-address=0.0.0.0:10911" \
       "--grpc-grace-period=1s" \
       "--http-address=0.0.0.0:10912" \
       "--http-grace-period=1s" \
       "--prometheus.url=http://$PROM_ADRESS" \
       "--tsdb.path=/data/prom$NAME" \
       
