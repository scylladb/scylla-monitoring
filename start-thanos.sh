#!/usr/bin/env bash

. versions.sh
if [ -f  env.sh ]; then
    . env.sh
fi

function usage {
  __usage="Usage: $(basename $0) [-h] [-S ip:port]

Options:
  -h print this help and exit
  -S sidecart address         - A side cart address:port multiple side cart can be comma delimited

The script starts Thanos query, it connect to external Thanos side carts and act as a grafana data source  
"
  echo "$__usage"
}

function update_data_source {
  THANOS_ADDRESS="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' thanos)"
  if [[ $THANOS_ADDRESS = "" ]]; then
      THANOS_ADDRESS=`hostname -I | awk '{print $1}'`
  fi
  THANOS_ADDRESS="$THANOS_ADDRESS:10904"
  __datasource="# config file version
apiVersion: 1
datasources:
- name: thanos
  type: prometheus
  url: http://$THANOS_ADDRESS
  access: proxy
  basicAuth: false
"
  echo "$__datasource" > grafana/provisioning/datasources/thanos.yaml
}
LIMITS=""
VOLUMES=""
PARAMS=""
for arg; do
    shift
    if [ -z "$LIMIT" ]; then
        case $arg in
            (--limit)
                LIMIT="1"
                ;;
            (--volume)
                LIMIT="1"
                VOLUME="1"
                ;;
            (--param)
                LIMIT="1"
                PARAM="1"
                ;;
            (*) set -- "$@" "$arg"
                ;;
        esac
    else
        DOCR=`echo $arg|cut -d',' -f1`
        VALUE=`echo $arg|cut -d',' -f2-|sed 's/#/ /g'`
        NOSPACE=`echo $arg|sed 's/ /#/g'`
        if [ "$PARAM" = "1" ]; then
            if [ -z "${DOCKER_PARAMS[$DOCR]}" ]; then
                DOCKER_PARAMS[$DOCR]=""
            fi
            DOCKER_PARAMS[$DOCR]="${DOCKER_PARAMS[$DOCR]} $VALUE"
            PARAMS="$PARAMS --param $NOSPACE"
            unset PARAM
        else
            if [ -z "${DOCKER_LIMITS[$DOCR]}" ]; then
                DOCKER_LIMITS[$DOCR]=""
            fi
            if [ "$VOLUME" = "1" ]; then
                SRC=`echo $VALUE|cut -d':' -f1`
                DST=`echo $VALUE|cut -d':' -f2-`
                SRC=$(readlink -m $SRC)
                DOCKER_LIMITS[$DOCR]="${DOCKER_LIMITS[$DOCR]} -v $SRC:$DST"
                VOLUMES="$VOLUMES --volume $NOSPACE"
                unset VOLUME
            else
                DOCKER_LIMITS[$DOCR]="${DOCKER_LIMITS[$DOCR]} $VALUE"
                LIMITS="$LIMITS --limit $NOSPACE"
            fi
        fi
        unset LIMIT
    fi
done
SIDECAR=()

DOCKER_PARAM=""
while getopts ':hlp:S:D:' option; do
  case "$option" in
    l) DOCKER_PARAM="$DOCKER_PARAM --net=host"
       ;;

    h) usage
       exit
       ;;
    S) IFS=',' ;for s in $OPTARG; do
         SIDECAR+=(--store=$s)
	   done
	   ;;
    D) DOCKER_PARAM="$DOCKER_PARAM $OPTARG"
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

docker run ${DOCKER_LIMITS["thanos"]} -d $DOCKER_PARAM -i --name thanos -- docker.io/thanosio/thanos:$THANOS_VERSION \
       query \
      "--debug.name=query0" \
      "--grpc-address=0.0.0.0:10903" \
      "--grpc-grace-period=1s" \
      "--http-address=0.0.0.0:10904" \
      "--http-grace-period=1s" \
      "--query.replica-label=prometheus" \
      ${DOCKER_PARAMS["thanos"]} \
      ${SIDECAR[@]}

update_data_source
