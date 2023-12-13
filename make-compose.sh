#!/usr/bin/env bash

. versions.sh
if [ -f  env.sh ]; then
    . env.sh
fi
DATA_SOURCES=""
CURRENT_VERSION="master"
LOKI_WALL_DIR="./loki-wall"
if [ -f CURRENT_VERSION.sh ]; then
    CURRENT_VERSION=`cat CURRENT_VERSION.sh`
fi

if [ -z "$BRANCH_VERSION" ]; then
  BRANCH_VERSION=$CURRENT_VERSION
fi
if [ -z ${DEFAULT_VERSION[$CURRENT_VERSION]} ]; then
    BRANCH_VERSION=`echo $CURRENT_VERSION|cut -d'.' -f1,2`
fi
if [ "$1" = "-e" ]; then
    DEFAULT_VERSION=${DEFAULT_ENTERPRISE_VERSION[$BRANCH_VERSION]}
fi

if [ -z "$MANAGER_VERSION" ];then
  MANAGER_VERSION=${MANAGER_DEFAULT_VERSION[$BRANCH_VERSION]}
fi

if [ "$CURRENT_VERSION" = "master" ]; then
    echo ""
    echo "*****************************************************"
    echo "* WARNING: You are using the unstable master branch *"
    echo "* Check the README.md file for the stable releases  *"
    echo "*****************************************************"
    echo ""
    echo "Make sure you run generate-dashboards.sh to generate your dashboards."
    echo 'For example to use Scylla 2021.1 run `./generate-dashboards.sh -F -v 2021.1`'
    echo ""
fi
if [ -z $LOKI_RULE_DIR ]; then
	LOKI_RULE_DIR=./loki/rules/scylla
fi
if [ -z $LOKI_CONF_DIR ]; then
	LOKI_CONF_DIR=./loki/conf
fi
if [ -z $PROMTAIL_CONFIG ]; then
	PROMTAIL_CONFIG=$PWD/loki/promtail/promtail_config.yml
fi
if [ "`id -u`" -eq 0 ]; then
    echo "Running as root is not advised, please check the documentation on how to run as non-root user"
else
    GROUPID=`id -g`
    PROMETHEUS_USER_PERMISSIONS="user: $UID:$GROUPID"
    LOKi_USER_PERMISSIONS="user: $UID:$GROUPID"
fi

if [[ $(uname) == "Linux" ]]; then
  readlink_command="readlink -f"
elif [[ $(uname) == "Darwin" ]]; then
  readlink_command="realpath "
fi

function usage {
  __usage="Usage: $(basename $0) [-h] [--version] [-e] [-d Prometheus data-dir] [-L resolve the servers from the manger running on the given address] [-G path to grafana data-dir] [-s scylla-target-file] [-n node-target-file] [-l] [-v comma separated versions] [-j additional dashboard to load to Grafana, multiple params are supported] [-c grafana environment variable, multiple params are supported] [-b Prometheus command line options] [-g grafana port ] [ -p prometheus port ] [-a admin password] [-m alertmanager port] [ -M scylla-manager version ] [-D encapsulate docker param] [-r alert-manager-config] [-R prometheus-alert-file] [-N manager target file] [-A bind-to-ip-address] [-C alertmanager commands] [-Q Grafana anonymous role (Admin/Editor/Viewer)] [-S start with a system specific dashboard set] [-T additional-prometheus-targets] [--no-loki] [--auto-restart] [--no-renderer] [-f alertmanager-dir]

Options:
  -h print this help and exit
  --version print the current monitoring version and the supported versions and exit.
  -e
  -d path/to/Prometheus/data/dir - Set an external data directory for the Prometheus data
  -L ip                          - Resolve the servers from a Scylla Manager running on the given address.
  -G path/to/Grafana/data-dir    - Set an external data directory for the Grafana data.
  -s path/to/scylla-target-file  - Read Scylla's target from the given file.
  -n path/to/node-target-file    - Override scylla target file for node_exporter.
  -l                             - If Set use the local host network, especially useful when a container needs
                                   to access the local host.
  -v comma separated versions    - Specify one or more Scylla versions, check --version for the supported versions.
  -j additional dashboard        - List additional dashboards to load to Grafana, multiple params are supported.
  -c grafana_environment         - Grafana environment variable, multiple params are supported.
  -b Prometheus command          - Prometheus command line options.
  -g grafana port                - Override the default Grafana port.
  -p prometheus port             - Override the default Prometheus port.
  -a admin password              - Set Grafna's Admin password.
  -m alertmanager port           - Override the default Prometheus port.
  -M scylla-manager version      - Override the default Scylla Manager version to use.
  -D docker param                - Encapsulate docker param, the parameter will be used by all containers.
  -r alert-manager-config        - Override the default alert-manager configuration file.
  -f path/to/alertmanager/data   - If set, the alertmanager would store its data in the given directory.
  -R prometheus-alert-file       - Override the default Prometheus alerts configuration file.
  -N path/to/manager/target file - Set the location of the target file for Scylla Manager.
  -A bind-to-ip-address          - Bind to a specific interface.
  -C alertmanager commands       - Pass the command to the alertmanager.
  -Q Grafana anonymous role      - Set the Grafana anonymous role to one of Admin/Editor/Viewer.
  -S dashbards-list              - Override the default set of dashboards with the spcefied one.
  -T path/to/prometheus-targets  - Adds additional Prometheus target files.
  -k path/to/loki/storage        - When set, will use the given directory for Loki's data
  --no-loki                      - If set, do not run Loki and promtail.
  --no-cas                       - If set, Prometheus will drop all cas related metrics while scrapping
  --no-cdc                       - If set, Prometheus will drop all cdc related metrics while scrapping
  --auto-restart                 - If set, auto restarts the containers on failure.
  --no-renderer                  - If set, do not run the Grafana renderer container.
  --thanos-sc                    - If set, run thanos side car with the Prometheus server.
  --thanos                       - If set, run thanos query as a Grafana datasource.
  --target-directory             - If set, prometheus/targets/ directory will be set as a root directory for the target files
                                   the file names should be scylla_server.yml, node_exporter_servers.yml, and  scylla_manager_servers.yml
  --limit container,param        - Allow to set a specific Docker parameter for a container, where container can be:
                                   prometheus, grafana, alertmanager, loki, sidecar, grafanarender
  --archive                      - Treat data directory as an archive. This disables Prometheus time-to-live (infinite retention).
The script starts Scylla Monitoring stack.
"
  echo "$__usage"
}

function is_local () {
    for var in "$@"; do
        if grep -q '\s127.' $1; then
            echo "Local host found in $1"
            grep '\s127.' $1
            return 0
        fi
        if grep -q 'localhost' $1; then
            return 0
        fi
    done
    return 1
}

function add_param() {
	arr=("$@")
	for value in "${arr[@]}"; do
        echo -n "    - $value\n"
    done
}

function set_path() {
	if [[ "$1" == "."* || "$1" == "/"* ]]; then
		echo $1
	else
		echo "./$1"
	fi
}

if [ -z "$GF_AUTH_BASIC_ENABLED" ]; then
	GF_AUTH_BASIC_ENABLED=false
fi

if [ -z "$GF_AUTH_ANONYMOUS_ENABLED" ]; then
	GF_AUTH_ANONYMOUS_ENABLED=true
fi
if [ -z "$GF_AUTH_ANONYMOUS_ORG_ROLE" ]; then
	GF_AUTH_ANONYMOUS_ORG_ROLE=Admin
fi
if [ -z "$GF_SECURITY_ADMIN_PASSWORD" ]; then
	GF_SECURITY_ADMIN_PASSWORD=admin
fi

if [ -z "$PROMETHEUS_RULES" ]; then
  PROMETHEUS_RULES="$PWD/prometheus/prom_rules/:/etc/prometheus/prom_rules/"
fi

if [ -z "$VERSIONS" ]; then
  VERSIONS=${DEFAULT_VERSION[$BRANCH_VERSION]}
fi

if [ -z "$SCYLLA_TARGET_FILES" ]; then
  SCYLLA_TARGET_FILES=($PWD/prometheus/scylla_servers.yml $PWD/scylla_servers.yml)
fi
if [ -z "$SCYLLA_MANGER_TARGET_FILES" ]; then
  SCYLLA_MANGER_TARGET_FILES=($PWD/prometheus/scylla_manager_servers.yml $PWD/scylla_manager_servers.yml $PWD/prometheus/scylla_manager_servers.example.yml)
fi
if [ -z "$GRAFANA_ADMIN_PASSWORD" ]; then
  GRAFANA_ADMIN_PASSWORD=""
fi

if [ -z "$ALERTMANAGER_PORT" ]; then
  ALERTMANAGER_PORT=""
fi

if [ -z "$LOKI_PORT" ]; then
	LOKI_PORT=3100
fi
if [ -z "$DOCKER_PARAM" ]; then
  DOCKER_PARAM=""
fi
if [ -z "$DATA_DIR" ]; then
  DATA_DIR=""
fi
if [ -z "$DATA_DIR_CMD" ]; then
  DATA_DIR_CMD=""
fi
if [ -z "$CONSUL_ADDRESS" ]; then
  CONSUL_ADDRESS=""
fi
if [ -z "$PROMETHEUS_TARGETS" ]; then
  PROMETHEUS_TARGETS=""
fi
if [ -z "$BIND_ADDRESS" ]; then
  BIND_ADDRESS=""
fi
if [ -z "$GRAFNA_ANONYMOUS_ROLE" ]; then
  GRAFNA_ANONYMOUS_ROLE=""
fi
if [ -z "$SPECIFIC_SOLUTION" ]; then
  SPECIFIC_SOLUTION=""
fi
if [ -z "$LDAP_FILE" ]; then
  LDAP_FILE=""
fi
if [ -z "$RUN_RENDERER" ]; then
  RUN_RENDERER="-E"
fi
if [ -z "$RUN_LOKI" ]; then
  RUN_LOKI=1
fi
if [ -z "$RUN_THANOS_SC" ]; then
  RUN_THANOS_SC=0
fi
if [ -z "$RUN_THANOS" ]; then
  RUN_THANOS=0
fi
if [ -z "$ALERT_MANAGER_DIR" ]; then
  ALERT_MANAGER_DIR=""
fi
if [ -z "$LOKI_DIR" ]; then
  LOKI_DIR=""
fi
for arg; do
    shift
    if [ -z "$LIMIT" ]; then
       case $arg in
            (--compose) RUN_COMPOSE=1
                ;;
            (--no-loki) RUN_LOKI=0
                ;;
            (--no-renderer) RUN_RENDERER=""
                ;;
            (--thanos-sc) RUN_THANOS_SC=1
                ;;
            (--thanos) RUN_THANOS=1
                ;;
            (--auto-restart) DOCKER_PARAM="$DOCKER_PARAM    restart: unless-stopped\n" 
                ;;
            (--victoria-metrics) VICTORIA_METRICS="1"
                ;;
            (--auth)
                GF_AUTH_BASIC_ENABLED="true"
                ;;
            (--disable-anonymous)
                GF_AUTH_ANONYMOUS_ENABLED="false"
                ;;
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
            (--evaluation-interval)
                LIMIT="1"
                PARAM="evaluation-interval"
                ;;
            (--manager-agents)
                LIMIT="1"
                PARAM="manager-agents"
                ;;
            (--datadog-api-keys)
                LIMIT="1"
                PARAM="datadog-api-keys"
                ;;
            (--datadog-hostname)
                LIMIT="1"
                PARAM="datadog-hostname"
                ;;
            (--version)
                echo "Scylla-Monitoring Stack version: $CURRENT_VERSION"
    			echo "Supported versions:" ${SUPPORTED_VERSIONS[$BRANCH_VERSION]}
    			echo "Manager supported versions:" ${MANAGER_SUPPORTED_VERSIONS[$BRANCH_VERSION]}
    			exit 0
            (--no-cas-cdc)
                PROMETHEUS_TARGETS="$PROMETHEUS_TARGETS --no-cas-cdc"
                ;;
            (--no-cas)
                PROMETHEUS_TARGETS="$PROMETHEUS_TARGETS --no-cas"
                ;;
            (--no-cdc)
                PROMETHEUS_TARGETS="$PROMETHEUS_TARGETS --no-cdc"
                ;;
            (--target-directory)
                LIMIT="1"
                PARAM="target-directory"
                ;;
            (--help) usage
                ;;
            (--archive)
                PROMETHEUS_COMMAND_LINE_OPTIONS_ARRAY+=(--storage.tsdb.retention.time=100y)
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
        elif [ "$PARAM" = "evaluation-interval" ]; then
            PROMETHEUS_TARGETS="$PROMETHEUS_TARGETS -E $NOSPACE"
            unset PARAM
        elif [ "$PARAM" = "manager-agents" ]; then
            SCYLLA_MANGER_AGENT_TARGET_FILE="$NOSPACE"
            unset PARAM
        elif [ "$PARAM" = "target-directory" ]; then
            TARGET_DIRECTORY="$NOSPACE"
            unset PARAM
        elif [ "$PARAM" = "datadog-api-keys" ]; then
            DATDOGPARAM="$DATDOGPARAM -A $NOSPACE"
            unset PARAM
        elif [ "$PARAM" = "datadog-hostname" ]; then
            DATDOGPARAM="$DATDOGPARAM -H $NOSPACE"
            unset PARAM
        else
            if [ -z "${DOCKER_LIMITS[$DOCR]}" ]; then
                DOCKER_LIMITS[$DOCR]=""
            fi
            if [ "$VOLUME" = "1" ]; then
                SRC=`echo $VALUE|cut -d':' -f1`
                DST=`echo $VALUE|cut -d':' -f2-`
                SRC=$($readlink_command "$SRC")
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

while getopts ':hleEd:g:p:v:s:n:a:c:j:b:m:r:R:M:G:D:L:N:C:Q:A:f:P:S:T:k:' option; do
  case "$option" in
    h) usage
       exit
       ;;
    v) VERSIONS=$OPTARG
       ;;
    M) MANAGER_VERSION=$OPTARG
       ;;
    d) DATA_DIR=$OPTARG
       ;;
    G) EXTERNAL_VOLUME="-G $OPTARG"
       ;;
    A) BIND_ADDRESS="$OPTARG:"
       ;;
    r) ALERT_MANAGER_RULE_CONFIG=$(set_path $OPTARG)
       ;;
    R) if [[ -d "$OPTARG" ]]; then
        PROMETHEUS_RULES=$($readlink_command $OPTARG)":/etc/prometheus/prom_rules/"
       else
        PROMETHEUS_RULES=$($readlink_command $OPTARG)":/etc/prometheus/prometheus.rules.yml"
       fi
       ;;
    g) GRAFANA_PORT="$OPTARG"
       ;;
    m) ALERTMANAGER_PORT="$OPTARG"
       ;;
    T) PROMETHEUS_TARGETS="$PROMETHEUS_TARGETS -T $OPTARG"
       ;;
    Q) GF_AUTH_ANONYMOUS_ORG_ROLE="$OPTARG"
       ;;
    p) PROMETHEUS_PORT=$OPTARG
       ;;
    s) SCYLLA_TARGET_FILES=("$OPTARG")
       ;;
    n) NODE_TARGET_FILE=$OPTARG
       ;;
    l) DOCKER_PARAM="$DOCKER_PARAM    network_mode: host\n"
       ;;
    L) CONSUL_ADDRESS="-L $OPTARG"
       ;;
    P) LDAP_FILE="-P $OPTARG"
       ;;
    a) GF_SECURITY_ADMIN_PASSWORD="$OPTARG"
       ;;
    j) GRAFANA_DASHBOARD_ARRAY+=("$OPTARG")
       ;;
    c) GRAFANA_ENV_ARRAY+=("$OPTARG")
       ;;
    C) ALERTMANAGER_COMMANDS+=("$OPTARG")
       ;;
    D) DOCKER_PARAM="$DOCKER_PARAM    $OPTARG\n"
       ;;
    b) PROMETHEUS_COMMAND_LINE_OPTIONS_ARRAY+=("$OPTARG")
       ;;
    N) SCYLLA_MANGER_TARGET_FILES=($OPTARG)
       ;;
    S) SPECIFIC_SOLUTION="-S $OPTARG"
       ;;
    E) RUN_RENDERER="-E"
       ;;
    f) ALERT_MANAGER_DIR=( $(set_path $OPTARG):/alertmanager/data:z) 
       ;;
    k) LOKI_DIR=`set_path $OPTARG`
       if [ ! -d $LOKI_DIR ]; then
           mkdir -p $LOKI_DIR
       fi
       LOKI_DIR="- $LOKI_DIR:/tmp/loki:z"
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

if [ -z "$VERSIONS" ]; then
  echo "Scylla-version was not not found, add the -v command-line with a specific version (i.e. -v 2021.1)"
  exit 1
fi

if [[ $DOCKER_PARAM = *"network_mode: host"* ]]; then
    if [ ! -z "$ALERTMANAGER_PORT" ] || [ ! -z "$GRAFANA_PORT" ] || [ ! -z $PROMETHEUS_PORT ]; then
        echo "Port mapping is not supported with host network, remove the -l flag from the command line"
        exit 1
    fi
    HOST_NETWORK=1
fi

if [ -z "$TARGET_DIRECTORY" ] && [ -z "$CONSUL_ADDRESS" ]; then
    for f in ${SCYLLA_TARGET_FILES[@]}; do
        if [ -f $f ]; then
            SCYLLA_TARGET_FILE=$f
            break
        fi
    done

    if [ -z $SCYLLA_TARGET_FILE ]; then
        echo "Scylla target file '${SCYLLA_TARGET_FILES}' does not exist, you can use prometheus/scylla_servers.example.yml as an example."
        exit 1
    fi

    if [ -z $NODE_TARGET_FILE ]; then
       PROMETHEUS_TARGETS="$PROMETHEUS_TARGETS --no-node-exporter-file"
       NODE_TARGET_FILE=$SCYLLA_TARGET_FILE
    fi

    if [ -z $SCYLLA_MANGER_AGENT_TARGET_FILE ]; then
       PROMETHEUS_TARGETS="$PROMETHEUS_TARGETS --no-manager-agent-file"
       SCYLLA_MANGER_AGENT_TARGET_FILE=$SCYLLA_TARGET_FILE
    fi
    if [ ! -f $NODE_TARGET_FILE ]; then
        echo "Node target file '${NODE_TARGET_FILE}' does not exist"
        exit 1
    fi

    for f in ${SCYLLA_MANGER_TARGET_FILES[@]}; do
        if [ -f $f ]; then
            SCYLLA_MANGER_TARGET_FILE=$f
            break
        fi
    done
    if [ -z $SCYLLA_MANGER_TARGET_FILE ]; then
        echo "Scylla-Manager target file '${SCYLLA_MANGER_TARGET_FILES}' does not exist, you can use prometheus/scylla_manager_servers.example.yml as an example."
        exit 1
    fi
    if [ -z "$HOST_NETWORK" ]; then
        if  is_local $SCYLLA_TARGET_FILE $SCYLLA_MANGER_TARGET_FILE $NODE_TARGET_FILE; then
            echo "Warning: It seems that you are trying to connect to localhost (either localhost or IP on the 127.x.x.x range)."
            echo "  For example, maybe Scylla Manager is running on the localhost."
            echo "If that is the case, you should set your Docker to use the host network. You can do that with the -l flag."
            echo ""
        fi
    fi
    SCYLLA_TARGET_FILE=$(set_path $SCYLLA_TARGET_FILE):/etc/scylla.d/prometheus/targets/scylla_servers.yml
    SCYLLA_MANGER_TARGET_FILE=$(set_path $SCYLLA_MANGER_TARGET_FILE):/etc/scylla.d/prometheus/targets/scylla_manager_servers.yml
    NODE_TARGET_FILE=$(set_path $NODE_TARGET_FILE)":/etc/scylla.d/prometheus/targets/node_exporter_servers.yml"
    SCYLLA_MANGER_AGENT_TARGET_FILE=$(set_path $SCYLLA_MANGER_AGENT_TARGET_FILE)":/etc/scylla.d/prometheus/targets/scylla_manager_agents.yml"
else
    SCYLLA_TARGET_FILE=""
    SCYLLA_MANGER_TARGET_FILE=""
    SCYLLA_MANGER_AGENT_TARGET_FILE=""
    NODE_TARGET_FILE=""
fi

if [ "$TARGET_DIRECTORY" != "" ]; then
    SCYLLA_TARGET_FILE=$(set_path $TARGET_DIRECTORY)":/etc/scylla.d/prometheus/targets/"
fi
if [ -z $DATA_DIR ]
then
    PROMETHEUS_USER_PERMISSIONS=""
    echo "Warning: without an external Prometheus directory, Prometheus data will be deleted on shutdown, use the -d command line flag for data persistence."
else
    if [ -d $DATA_DIR ]; then
        echo "Loading prometheus data from $DATA_DIR"
    else
        echo "Creating data directory $DATA_DIR"
        mkdir -p $DATA_DIR
    fi
    if [[ "$VICTORIA_METRICS" = "1" ]]; then
    	PROMETHEUS_PROMETHEUS_VOLUMES_ARRAY+=($(set_path $DATA_DIR)":/victoria-metrics-data")
    else
        PROMETHEUS_PROMETHEUS_VOLUMES_ARRAY+=($(set_path $DATA_DIR)":/prometheus/data:Z")
    fi
fi

if (( ${#ALERTMANAGER_COMMANDS[@]} )); then
    ALERTMANAGER_COMMAND="    command:\n"`add_param "${ALERTMANAGER_COMMANDS[@]}"`
fi

if [ -z $PROMETHEUS_PORT ]; then
    PROMETHEUS_PORT=9090
fi
if [ -z $ALERTMANAGER_PORT ]; then
    ALERTMANAGER_PORT=9093
fi
if [ -z $GRAFANA_PORT ]; then
    GRAFANA_PORT=3000
fi
DATA_SOURCES="-p aprom:$PROMETHEUS_PORT -m $ALERTMANAGER_ADDRESS -L loki:$LOKI_PORT"
ALERTMANAGER_ADDRESS="aalert:$ALERTMANAGER_PORT"
if [[ "$HOST_NETWORK" = "1" ]]; then
    ALERTMANAGER_ADDRESS="127.0.0.1:$ALERTMANAGER_PORT"
    DATA_SOURCES="-p 127.0.0.1:$PROMETHEUS_PORT -m $ALERTMANAGER_ADDRESS -L 127.0.0.1:$LOKI_PORT"
fi

if [[ ! -d $LOKI_WALL_DIR ]]; then
	echo "loki WALL directory does not exists"
fi

if [ -z $ALERT_MANAGER_RULE_CONFIG ]; then
	ALERT_MANAGER_RULE_CONFIG=./prometheus/rule_config.yml
fi
cat docker-compose.template.yml > docker-compose.yml
echo "" > .env
echo "PROMETHEUS_VERSION=$PROMETHEUS_VERSION" >> .env
echo "ALERT_MANAGER_VERSION=$ALERT_MANAGER_VERSION" >> .env
echo "GRAFANA_VERSION=$GRAFANA_VERSION" >> .env
echo "LOKI_VERSION=$LOKI_VERSION" >> .env
echo "GRAFANA_RENDERER_VERSION=$GRAFANA_RENDERER_VERSION" >> .env
echo "THANOS_VERSION=$THANOS_VERSION" >> .env
echo "VICTORIA_METRICS_VERSION=$VICTORIA_METRICS_VERSION" >> .env
echo "GF_AUTH_BASIC_ENABLED=$GF_AUTH_BASIC_ENABLED" >> .env
echo "GF_AUTH_ANONYMOUS_ENABLED=$GF_AUTH_ANONYMOUS_ENABLED" >> .env
echo "GF_AUTH_ANONYMOUS_ORG_ROLE=$GF_AUTH_ANONYMOUS_ORG_ROLE" >> .env
echo "GF_SECURITY_ADMIN_PASSWORD=$GF_SECURITY_ADMIN_PASSWORD" >> .env
echo "SCYLLA_VERSION=$VERSIONS" >> .env
echo "ALERTMANAGER_PORT=$ALERTMANAGER_PORT" >> .env
echo "GRAFANA_PORT=$GRAFANA_PORT" >> .env
echo "PROMETHEUS_PORT=$PROMETHEUS_PORT" >> .env
echo "ALERT_MANAGER_RULE_CONFIG=$ALERT_MANAGER_RULE_CONFIG" >> .env
echo "PROMETHEUS_RULES=$PROMETHEUS_RULES">> .env
echo "BIND_ADDRESS=$BIND_ADDRESS">> .env
echo "SCYLLA_TARGET_FILE=$SCYLLA_TARGET_FILE">> .env
echo "SCYLLA_MANGER_TARGET_FILE=$SCYLLA_MANGER_TARGET_FILE">> .env
echo "SCYLLA_MANGER_AGENT_TARGET_FILE=$SCYLLA_MANGER_AGENT_TARGET_FILE">> .env
echo "NODE_TARGET_FILE=$NODE_TARGET_FILE">> .env
echo "LOKI_RULE_DIR=$LOKI_RULE_DIR">> .env
echo "LOKI_CONF_DIR=$LOKI_CONF_DIR">> .env
echo "LOKI_DIR=$LOKI_DIR">> .env
echo "LOKI_PORT=$LOKI_PORT">> .env
echo "LOKI_WALL_DIR=$LOKI_WALL_DIR">> .env
if [ "$VICTORIA_METRICS" = "1" ]; then
	sed -i 's&prom/prometheus:${PROMETHEUS_VERSION}&victoriametrics/victoria-metrics:${VICTORIA_METRICS_VERSION}&' docker-compose.yml
	sed -i 's&./prometheus/build/prometheus.yml:/etc/prometheus/prometheus.yml&./prometheus/build/prometheus.yml:/etc/promscrape.config.yml:z&' docker-compose.yml
	PROMETHEUS_COMMAND_LINE_OPTIONS_ARRAY+=( -promscrape.config=/etc/promscrape.config.yml -promscrape.config.strictParse=false -httpListenAddr=:9090)
else
	PROMETHEUS_COMMAND_LINE_OPTIONS_ARRAY+=(--config.file=/etc/prometheus/prometheus.yml --web.enable-lifecycle)
fi
PROMETHEUS_COMMAND_LINE=""
if (( ${#PROMETHEUS_COMMAND_LINE_OPTIONS_ARRAY[@]} )); then
    PROMETHEUS_COMMAND_LINE="    command:\n"`add_param "${PROMETHEUS_COMMAND_LINE_OPTIONS_ARRAY[@]}"`
fi

sed -i "s& *#PROMETHEUS_COMMAND_LINE&$PROMETHEUS_COMMAND_LINE&" docker-compose.yml
val=`add_param "${PROMETHEUS_PROMETHEUS_VOLUMES_ARRAY[@]}"`
sed -i "s& *#PROMETHEUS_VOLUMES&$val&" docker-compose.yml

val=`add_param "${GRAFANA_ENV_ARRAY[@]}"`
sed -i "s& *#GRAFANA_ENV&$val&" docker-compose.yml

sed -i "s& *#GENERAL_DOCER_CONFIG&$DOCKER_PARAM&" docker-compose.yml
sed -i "s& *#ALERT_MANAGER_DIR&$ALERT_MANAGER_DIR&" docker-compose.yml
sed -i "s& *#ALERTMANAGER_COMMAND&$ALERTMANAGER_COMMAND&" docker-compose.yml
sed -i "s&#PROMETHEUS_USER_PERMISSIONS&$PROMETHEUS_USER_PERMISSIONS&" docker-compose.yml
sed -i "s&#LOKI_DIR&$LOKI_DIR&" docker-compose.yml
sed -i "s&#LOKi_USER_PERMISSIONS&$LOKi_USER_PERMISSIONS&" docker-compose.yml

./prometheus-config.sh -m $ALERTMANAGER_ADDRESS $CONSUL_ADDRESS $PROMETHEUS_TARGETS
for val in "${GRAFANA_DASHBOARD_ARRAY[@]}"; do
        GRAFANA_DASHBOARD_COMMAND="$GRAFANA_DASHBOARD_COMMAND -j $val"
done
./generate-dashboards.sh -t $SPECIFIC_SOLUTION -v $VERSIONS -M $MANAGER_VERSION $GRAFANA_DASHBOARD_COMMAND

./grafana-datasource.sh $DATA_SOURCES

if [ "$RUN_COMPOSE" = "1" ]; then
	docker-compose up
fi
