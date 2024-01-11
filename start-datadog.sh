#!/usr/bin/env bash
if [ -f  env.sh ]; then
    . env.sh
fi
usage="$(basename "$0") [-h] [-A DD_API_KEY ][-p ip:port address of prometheus ] [-d configuration directory] [-e environment variable, multiple params are supported] [-D encapsulate docker param] -- Start a datadog agent inside a container"

while getopts ':hA:p:e:H:D:' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    A) DD_API_KEY=$OPTARG
       ;;
    D) DOCKER_PARAM="$DOCKER_PARAM $OPTARG"
       ;;
    H) hostname="$OPTARG"
       ;;
    e) ENV_ARRAY+=("$OPTARG")
       ;;
    d) CONF_DIR="$OPTARG"
       ;;
    p) PROMIP="$OPTARG"
       ;;
    l) DOCKER_PARAM="$DOCKER_PARAM --net=host"
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

if [ -z "$DD_API_KEY" ]; then
	printf "\nDatagot API keys are not present, exiting.\n"
    exit 1
fi
if [ -z "$DATADOG_NAME" ]; then
    DATADOG_NAME="datadog-agent"
fi

docker container inspect $DATADOG_NAME > /dev/null 2>&1
if [ $? -eq 0 ]; then
    printf "\nSome of the monitoring docker instances ($DATADOG_NAME) exist. Make sure all containers are killed and removed. You can use kill-all.sh for that\n"
    exit 1
fi

group_args=()
is_podman="$(docker --help | grep -o podman)"
if [ ! -z "$is_podman" ]; then
    group_args+=(--userns=keep-id)
fi

if [ -z "$CONF_DIR" ]; then
    CONF_DIR="datadog_conf"
fi

for val in "${ENV_ARRAY[@]}"; do
        ENV_COMMAND="$ENV_COMMAND -e $val"
done

if [[ -z "${DOCKER_HOST}" ]]; then
    if [ ! -z "$is_podman" ]; then
        if [[ $(uname) == "Linux" ]]; then
            DOCKER_HOST=$(hostname -I | awk '{print $1}')
        elif [[ $(uname) == "Darwin" ]]; then
            DOCKER_HOST=$(ifconfig bridge0 | awk '/inet / {print $2}')
        fi
    else
        if [[ $(uname) == "Linux" ]]; then
            DOCKER_HOST=$(ip -4 addr show docker0 | grep -Po 'inet \K[\d.]+')
        elif [[ $(uname) == "Darwin" ]]; then
            DOCKER_HOST=$(ifconfig bridge0 | awk '/inet / {print $2}')
        fi
    fi
fi

if [[ $(uname) == "Linux" ]]; then
  readlink_command="readlink -f"
elif [[ $(uname) == "Darwin" ]]; then
  readlink_command="realpath "
fi

if [ -z "$hostname" ]; then
    hostname=$HOSTNAME
fi
    
mkdir -p $CONF_DIR/conf.d/prometheus.d
if [ ! -f $CONF_DIR/datadog.yaml ]; then
    cat >$CONF_DIR/datadog.yaml <<EOL
# datadog.yaml
process_config:
  enabled: true
  scrub_args: true
logs_enabled: true
confd_path: /conf.d
log_level: INFO
hostname: ${hostname}
EOL
fi
cat docs/source/procedures/datadog/conf.yaml|sed "s/IP:9090/$PROMIP/g" > $CONF_DIR/conf.d/prometheus.d/conf.yaml

CONF_DIR=$($readlink_command "$CONF_DIR")

docker run -d $DOCKER_PARAM ${DOCKER_LIMITS["datadog"]} -i \
--name $DATADOG_NAME \
--pid host -v $CONF_DIR/datadog.yaml:/etc/datadog-agent/datadog.yaml \
-v $CONF_DIR/conf.d/:/conf.d \
$ENV_COMMAND \
-e DD_API_KEY="$DD_API_KEY" -e DD_CONTAINER_INCLUDE="" gcr.io/datadoghq/agent:latest
