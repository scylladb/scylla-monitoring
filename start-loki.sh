#!/usr/bin/env bash

is_podman="$(docker --help | grep -o podman)"
. versions.sh
if [ -f  env.sh ]; then
    . env.sh
fi

VERSIONS=$DEFAULT_VERSION
LOKI_RULE_DIR=$PWD/loki/rules/scylla
LOKI_CONF_DIR=$PWD/loki/conf
PROMTAIL_CONFIG=$PWD/loki/promtail/promtail_config.yml
DOCKER_PARAM=""
BIND_ADDRESS=""
LOKI_COMMANDS="--ingester.wal-enabled=false"
LOKI_DIR=""
usage="$(basename "$0") [-h] [-l] [-D encapsulate docker param] [-m alert_manager address]"
if [ "`id -u`" -ne 0 ]; then
    GROUPID=`id -g`
    USER_PERMISSIONS="-u $UID:$GROUPID"
fi
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
while getopts ':hlp:D:m:A:k:' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    p) LOKI_PORT=$OPTARG
       ;;
    r) LOKI_RULE_DIR=`readlink -m $OPTARG`
       ;;
    l) DOCKER_PARAM="$DOCKER_PARAM --net=host"
       ;;
    D) DOCKER_PARAM="$DOCKER_PARAM $OPTARG"
       ;;
    C) LOKI_COMMANDS="$LOKI_COMMANDS $OPTARG"
       ;;
    A) BIND_ADDRESS="$OPTARG:"
       ;;
    k) LOKI_DIR=`readlink -m $OPTARG`
       if [ ! -d $LOKI_DIR ]; then
           mkdir -p $LOKI_DIR
       fi
       LOKI_DIR="-v $LOKI_DIR:/tmp/loki:z"
       ;;
    m) ALERT_MANAGER_ADDRESS=$OPTARG
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
if [ -z $LOKI_PORT ]; then
    LOKI_PORT=3100
    LOKI_NAME=loki
else
    LOKI_NAME=loki-$LOKI_PORT
fi

if [[ $LOKI_DIR = "" ]]; then
  USER_PERMISSIONS=""
fi

docker container inspect $LOKI_NAME > /dev/null 2>&1
if [ $? -eq 0 ]; then
    printf "\nSome of the monitoring docker instances ($LOKI_NAME) exist. Make sure all containers are killed and removed. You can use kill-all.sh for that\n"
    exit 1
fi

if [[ ! $DOCKER_PARAM = *"--net=host"* ]]; then
    PORT_MAPPING="-p $BIND_ADDRESS$LOKI_PORT:3100"
fi

if [ -z $ALERT_MANAGER_ADDRESS ]; then
	ALERT_MANAGER_ADDRESS="$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' aalert):9093"
fi

sed "s/ALERTMANAGER/$ALERT_MANAGER_ADDRESS/" loki/conf/loki-config.template.yaml > loki/conf/loki-config.yaml

docker run ${DOCKER_LIMITS["loki"]} -d $DOCKER_PARAM -i $PORT_MAPPING \
     $USER_PERMISSIONS \
	 -v $LOKI_RULE_DIR:/etc/loki/rules/fake:z \
	 -v $LOKI_CONF_DIR:/mnt/config:z \
	 $LOKI_DIR \
     --name $LOKI_NAME docker.io/grafana/loki:$LOKI_VERSION $LOKI_COMMANDS --config.file=/mnt/config/loki-config.yaml ${DOCKER_PARAMS["loki"]} >& /dev/null

if [ $? -ne 0 ]; then
    echo "Error: Loki container failed to start"
    echo "For more information use: docker logs $LOKI_NAME"
    exit 1
fi

# Wait till Loki is available
RETRIES=5
TRIES=0
until $(curl --output /dev/null -f --silent http://localhost:$LOKI_PORT) || [ $TRIES -eq $RETRIES ]; do
    ((TRIES=TRIES+1))
    sleep 5
done

if [ ! "$(docker ps -q -f name=$LOKI_NAME)" ]
then
    echo "Error: Loki container failed to start"
    exit 1
fi

LOKI_ADDRESS="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $LOKI_NAME):3100"
if [ "$LOKI_ADDRESS" = ":3100" ]; then
    if [[ $(uname) == "Linux" ]]; then
        HOST_IP=$(hostname -I | awk '{print $1}')
    elif [[ $(uname) == "Darwin" ]]; then
        HOST_IP=$(ifconfig en0 | awk '/inet / {print $2}')
    fi
    LOKI_ADDRESS="$HOST_IP:3100"
fi


if [ -z $PROMTAIL_PORT ]; then
    PROMTAIL_PORT=9080
    PROMTAIL_NAME=promtail
else
    PROMTAIL_NAME=promtail-$PROMTAIL_PORT
fi

docker container inspect $PROMTAIL_NAME > /dev/null 2>&1
if [ $? -eq 0 ]; then
    printf "\nSome of the monitoring docker instances ($PROMTAIL_NAME) exist. Make sure all containers are killed and removed. You can use kill-all.sh for that\n"
    exit 1
fi

if [[ ! $DOCKER_PARAM = *"--net=host"* ]]; then
    PROMTAIL_PORT_MAPPING="-p $BIND_ADDRESS$PROMTAIL_PORT:9080 -p ${BIND_ADDRESS}1514:1514"
fi

sed "s/LOKI_IP/$LOKI_ADDRESS/" loki/promtail/promtail_config.template.yml > loki/promtail/promtail_config.yml

docker run ${DOCKER_LIMITS["promtail"]}  -d $DOCKER_PARAM -i $PROMTAIL_PORT_MAPPING \
	 -v $PROMTAIL_CONFIG:/etc/promtail/config.yml:z \
     --name $PROMTAIL_NAME docker.io/grafana/promtail:$LOKI_VERSION --config.file=/etc/promtail/config.yml ${DOCKER_PARAMS["promtail"]} >& /dev/null

if [ $? -ne 0 ]; then
    echo "Error: Promtail container failed to start"
    echo "For more information use: docker logs $PROMTAIL_NAME"
    exit 1
fi

# Wait till Loki is available
RETRIES=5
TRIES=0
until $(curl --output /dev/null -f --silent http://localhost:$PROMTAIL_PORT) || [ $TRIES -eq $RETRIES ]; do
    ((TRIES=TRIES+1))
    sleep 5
done

if [ ! "$(docker ps -q -f name=$PROMTAIL_NAME)" ]
then
    echo "Error: Promtail container failed to start"
    exit 1
fi

echo "$LOKI_ADDRESS"
