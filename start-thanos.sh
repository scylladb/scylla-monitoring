#!/usr/bin/env bash

. versions.sh
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
  THANOS_ADDRESS="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' thanos):10904"
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
SIDECAR=()

while getopts ':hl:p:S:' option; do
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

docker run ${DOCKER_LIMITS["thanos"]} -d $DOCKER_PARAM -i --name thanos -- thanosio/thanos:$THANOS_VERSION \
       query \
      "--debug.name=query0" \
      "--log.level=debug" \
      "--grpc-address=0.0.0.0:10903" \
      "--grpc-grace-period=1s" \
      "--http-address=0.0.0.0:10904" \
      "--http-grace-period=1s" \
      "--query.replica-label=prometheus" \
      ${SIDECAR[@]}

update_data_source
