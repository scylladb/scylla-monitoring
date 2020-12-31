#!/usr/bin/env bash

if [ "$1" = "-e" ]; then
. enterprise_versions.sh
else
. versions.sh
fi
VERSIONS=$DEFAULT_VERSION

GRAFANA_VERSION=7.3.5
LOCAL=""
GRAFANA_ADMIN_PASSWORD="admin"
GRAFANA_AUTH=false
GRAFANA_AUTH_ANONYMOUS=true
DOCKER_PARAM=""
EXTERNAL_VOLUME=""
BIND_ADDRESS=""
ANONYMOUS_ROLE="Admin"
SPECIFIC_SOLUTION=""
LDAP_FILE=""

DATA_SOURCES=""

usage="$(basename "$0") [-h] [-v comma separated versions ] [-g grafana port ] [-G path to external dir] [-n grafana container name ] [-p ip:port address of prometheus ] [-j additional dashboard to load to Grafana, multiple params are supported] [-c grafana enviroment variable, multiple params are supported] [-x http_proxy_host:port] [-m alert_manager address] [-a admin password] [ -M scylla-manager version ] [-D encapsulate docker param] [-Q Grafana anonymous role (Admin/Editor/Viewer)] [-S start with a system specific dashboard set] [-P ldap_config_file] -- loads the prometheus datasource and the Scylla dashboards into an existing grafana installation"

while getopts ':hlEg:n:p:v:a:x:c:j:m:G:M:D:A:S:P:L:Q:' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    v) VERSIONS=$OPTARG
       ;;
    M) MANAGER_VERSION=$OPTARG
       ;;
    g) GRAFANA_PORT=$OPTARG
       ;;
    G) EXTERNAL_VOLUME="-v "`readlink -m $OPTARG`":/var/lib/grafana"
       ;;
    n) GRAFANA_NAME=$OPTARG
       ;;
    p) DATA_SOURCES="$DATA_SOURCES -p $OPTARG"
       ;;
    m) DATA_SOURCES="$DATA_SOURCES -m $OPTARG"
       ;;
    L) DATA_SOURCES="$DATA_SOURCES -L $OPTARG"
       ;;
    l) DOCKER_PARAM="$DOCKER_PARAM --net=host"
       ;;
    P) LDAP_FILE="$OPTARG"
       GRAFANA_ENV_ARRAY+=("GF_AUTH_LDAP_ENABLED=true" "GF_AUTH_LDAP_CONFIG_FILE=/etc/grafana/ldap.toml" "GF_AUTH_LDAP_ALLOW_SIGN_UP=true")
       LDAP_FILE="-v "`readlink -m $OPTARG`":/etc/grafana/ldap.toml"
       GRAFANA_AUTH=true
       GRAFANA_AUTH_ANONYMOUS=false
       ;;
    D) DOCKER_PARAM="$DOCKER_PARAM $OPTARG"
       ;;
    Q) ANONYMOUS_ROLE=$OPTARG
       ;;
    a) GRAFANA_ADMIN_PASSWORD=$OPTARG
       GRAFANA_AUTH=true
       GRAFANA_AUTH_ANONYMOUS=false
       ;;
    x) HTTP_PROXY="$OPTARG"
       ;;
    c) GRAFANA_ENV_ARRAY+=("$OPTARG")
       ;;
    j) GRAFANA_DASHBOARD_ARRAY+=("$OPTARG")
       ;;
    A) BIND_ADDRESS="$OPTARG:"
       ;;
    S) SPECIFIC_SOLUTION="-S $OPTARG"
       ;;
    E) RUN_RENDERER="-E"
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

if [ -z $GRAFANA_PORT ]; then
    GRAFANA_PORT=3000
    if [ -z $GRAFANA_NAME ]; then
        GRAFANA_NAME=agraf
    fi
fi

if [ -z $GRAFANA_NAME ]; then
    GRAFANA_NAME=agraf-$GRAFANA_PORT
fi

docker container inspect $GRAFANA_NAME > /dev/null 2>&1
if [ $? -eq 0 ]; then
    printf "\nSome of the monitoring docker instances ($GRAFANA_NAME) exist. Make sure all containers are killed and removed. You can use kill-all.sh for that\n"
    exit 1
fi

group_args=()
is_podman="$(docker --help | grep -o podman)"
if [ ! -z "$is_podman" ]; then
    group_args+=(--userns=keep-id)
fi

if [ "`id -u`" -ne 0 ]; then
    GROUPID=`id -g`
    USER_PERMISSIONS="-u $UID:$GROUPID"
fi

proxy_args=()
if [[ -n "$HTTP_PROXY" ]]; then
    proxy_args=(-e http_proxy="$HTTP_PROXY")
fi

for val in "${GRAFANA_ENV_ARRAY[@]}"; do
        GRAFANA_ENV_COMMAND="$GRAFANA_ENV_COMMAND -e $val"
done


for val in "${GRAFANA_DASHBOARD_ARRAY[@]}"; do
        GRAFANA_DASHBOARD_COMMAND="$GRAFANA_DASHBOARD_COMMAND -j $val"
done

./generate-dashboards.sh -t $SPECIFIC_SOLUTION -v $VERSIONS -M $MANAGER_VERSION $GRAFANA_DASHBOARD_COMMAND
./grafana-datasource.sh $DATA_SOURCES

if [[ ! $DOCKER_PARAM = *"--net=host"* ]]; then
    PORT_MAPPING="-p $BIND_ADDRESS$GRAFANA_PORT:3000"
fi

if [ ! -d $EXTERNAL_VOLUME ]; then
    echo "Creating grafana directory directory $EXTERNAL_VOLUME"
    mkdir -p $EXTERNAL_VOLUME
fi

if [ ! -z $RUN_RENDERER ]; then
	if [ ! -z "$is_podman" ]; then
		DOCKER_HOST=`hostname -I | awk '{print $1}'`
	else
		DOCKER_HOST=$(ip -4 addr show docker0 | grep -Po 'inet \K[\d.]+')
	fi
    RENDERING_SERVER_URL=`./start-grafana-renderer.sh -D "$DOCKER_PARAM"`
    GRAFANA_ENV_COMMAND="$GRAFANA_ENV_COMMAND -e GF_RENDERING_SERVER_URL=http://$DOCKER_HOST:8081/render -e GF_RENDERING_CALLBACK_URL=http://$DOCKER_HOST:$GRAFANA_PORT/"
fi


docker run -d $DOCKER_PARAM -i $USER_PERMISSIONS $PORT_MAPPING \
     -e "GF_AUTH_BASIC_ENABLED=$GRAFANA_AUTH" \
     -e "GF_AUTH_ANONYMOUS_ENABLED=$GRAFANA_AUTH_ANONYMOUS" \
     -e "GF_AUTH_ANONYMOUS_ORG_ROLE=$ANONYMOUS_ROLE" \
     -e "GF_PANELS_DISABLE_SANITIZE_HTML=true" \
     $LDAP_FILE \
     "${group_args[@]}" \
     -v $PWD/grafana/build:/var/lib/grafana/dashboards:z \
     -v $PWD/grafana/plugins:/var/lib/grafana/plugins:z \
     -v $PWD/grafana/provisioning:/var/lib/grafana/provisioning:z $EXTERNAL_VOLUME \
     -e "GF_PATHS_PROVISIONING=/var/lib/grafana/provisioning" \
     -e "GF_SECURITY_ADMIN_PASSWORD=$GRAFANA_ADMIN_PASSWORD" \
     -e "GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=scylladb-scylla-datasource" \
     $GRAFANA_ENV_COMMAND \
     "${proxy_args[@]}" \
     --name $GRAFANA_NAME grafana/grafana:$GRAFANA_VERSION >& /dev/null

if [ $? -ne 0 ]; then
    echo "Error: Grafana container failed to start"
    echo "For more information use: docker logs $GRAFANA_NAME"
    exit 1
fi

# Wait till Grafana API is available
printf "Wait for Grafana container to start."
RETRIES=7
TRIES=0
until $(curl --output /dev/null -f --silent http://localhost:$GRAFANA_PORT/api/org) || [ $TRIES -eq $RETRIES ]; do
    printf '.'
    ((TRIES=TRIES+1))
    sleep 5
done
echo
if [ ! "$(docker ps -q -f name=$GRAFANA_NAME)" ]
then
        echo "Error: Grafana container failed to start"
        echo "For more information use: docker logs $GRAFANA_NAME"
        exit 1
fi
if [ -z "$BIND_ADDRESS" ]; then
    BIND_ADDRESS="localhost:"
fi
printf "Start completed successfully, check http://$BIND_ADDRESS$GRAFANA_PORT\n"
