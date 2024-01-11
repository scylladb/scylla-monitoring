#!/usr/bin/env bash
CURRENT_VERSION="master"
if [ -f CURRENT_VERSION.sh ]; then
    CURRENT_VERSION=`cat CURRENT_VERSION.sh`
fi
LOCAL=""
if [ -z "$GRAFANA_ADMIN_PASSWORD" ]; then
    GRAFANA_ADMIN_PASSWORD="admin"
fi
if [ -z "$GRAFANA_AUTH" ]; then
    GRAFANA_AUTH=false
fi
if [ -z "$GRAFANA_AUTH_ANONYMOUS" ]; then
    GRAFANA_AUTH_ANONYMOUS=true
fi
EXTERNAL_VOLUME=""
BIND_ADDRESS=""
if [ -z "$ANONYMOUS_ROLE" ]; then
    ANONYMOUS_ROLE="Admin"
fi
SPECIFIC_SOLUTION=""
LDAP_FILE=""

DATA_SOURCES=""
LIMITS=""
VOLUMES=""
PARAMS=""
DEFAULT_THEME="light"
. versions.sh
. UA.sh
if [ -f  env.sh ]; then
    . env.sh
fi
DOCKER_PARAM=""

BRANCH_VERSION=$CURRENT_VERSION
if [ -z ${DEFAULT_VERSION[$CURRENT_VERSION]} ]; then
    BRANCH_VERSION=`echo $CURRENT_VERSION|cut -d'.' -f1,2`
fi

if [ "$1" = "-e" ]; then
    DEFAULT_VERSION=${DEFAULT_ENTERPRISE_VERSION[$BRANCH_VERSION]}
fi
MANAGER_VERSION=${MANAGER_DEFAULT_VERSION[$BRANCH_VERSION]}
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
            (--auth)
                GRAFANA_AUTH=true
                ;;
            (--disable-anonymous)
                GRAFANA_AUTH_ANONYMOUS=false
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
usage="$(basename "$0") [-h] [-v comma separated versions ] [-g grafana port ] [-G path to external dir] [-n grafana container name ] [-p ip:port address of prometheus ] [-j additional dashboard to load to Grafana, multiple params are supported] [-c grafana environment variable, multiple params are supported] [-x http_proxy_host:port] [-m alert_manager address] [-a admin password] [ -M scylla-manager version ] [-D encapsulate docker param] [-Q Grafana anonymous role (Admin/Editor/Viewer)] [-S start with a system specific dashboard set] [-P ldap_config_file] -- loads the prometheus datasource and the Scylla dashboards into an existing grafana installation"

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
       if [ ! -d $OPTARG ]; then
         echo "Creating grafana external directory $OPTARG"
         mkdir -p $OPTARG
       fi
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
VERSION=`echo $VERSIONS|cut -d',' -f1`
if [ "$VERSION" = "" ]; then
    echo "Scylla-version was not not found, add the -v command-line with a specific version (i.e. -v 2021.1)"
    exit 1
fi

if [ "$VERSION" = "latest" ]; then
    if [ -z "$BRANCH_VERSION" ] || [ "$BRANCH_VERSION" = "master" ]; then
        echo "Default versions (-v latest) is not supported on the master branch, use specific version instead"
        exit 1
    fi
    VERSION=${DEFAULT_VERSION[$BRANCH_VERSION]}
    echo "The use of -v latest is deprecated. Use a specific version instead."
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
        if [[ $val == GF_USERS_DEFAULT_THEME=* ]]; then
            DEFAULT_THEME=""
        fi
done
if [[ $DEFAULT_THEME != "" ]]; then
    GRAFANA_ENV_COMMAND="$GRAFANA_ENV_COMMAND -e GF_USERS_DEFAULT_THEME=$DEFAULT_THEME"
fi

for val in "${GRAFANA_DASHBOARD_ARRAY[@]}"; do
        GRAFANA_DASHBOARD_COMMAND="$GRAFANA_DASHBOARD_COMMAND -j $val"
done

./generate-dashboards.sh -t $SPECIFIC_SOLUTION -v $VERSIONS -M $MANAGER_VERSION $GRAFANA_DASHBOARD_COMMAND
./grafana-datasource.sh $DATA_SOURCES

if [[ ! $DOCKER_PARAM = *"--net=host"* ]]; then
    PORT_MAPPING="-p $BIND_ADDRESS$GRAFANA_PORT:3000"
fi

if [[ "$HOME_DASHBOARD" = "" ]]; then
    HOME_DASHBOARD="/var/lib/grafana/dashboards/ver_$VERSION/scylla-overview.$VERSION.json"
fi

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

if [ ! -z $RUN_RENDERER ]; then
	if [ ! -z "$is_podman" ]; then
		HOST_ADDRESS=`hostname -I | awk '{print $1}'`
	else
		HOST_ADDRESS=$(ip -4 addr show docker0 | grep -Po 'inet \K[\d.]+')
	fi
    RENDERING_SERVER_URL=`./start-grafana-renderer.sh $LIMITS $VOLUMES $PARAMS  -D "$DOCKER_PARAM"`
    GRAFANA_ENV_COMMAND="$GRAFANA_ENV_COMMAND -e GF_RENDERING_SERVER_URL=http://$HOST_ADDRESS:8081/render -e GF_RENDERING_CALLBACK_URL=http://$HOST_ADDRESS:$GRAFANA_PORT/"
fi

docker run -d $DOCKER_PARAM ${DOCKER_LIMITS["grafana"]} -i $USER_PERMISSIONS $PORT_MAPPING \
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
     -e "GF_ANALYTICS_GOOGLE_ANALYTICS_UA_ID=$UA_ANALTYICS" \
     -e "GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=scylladb-scylla-datasource" \
     -e "GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=$HOME_DASHBOARD" \
     $GRAFANA_ENV_COMMAND \
     "${proxy_args[@]}" \
     --name $GRAFANA_NAME docker.io/grafana/grafana:$GRAFANA_VERSION ${DOCKER_PARAMS["grafana"]} >& /dev/null

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
