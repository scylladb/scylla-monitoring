#!/usr/bin/env bash

. versions.sh
if [ -f  env.sh ]; then
    . env.sh
fi

CURRENT_VERSION="master"
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

if [ "$1" = "--version" ]; then
    echo "Scylla-Monitoring Stack version: $CURRENT_VERSION"
    echo "Supported versions:" ${SUPPORTED_VERSIONS[$BRANCH_VERSION]}
    echo "Manager supported versions:" ${MANAGER_SUPPORTED_VERSIONS[$BRANCH_VERSION]}
    exit
fi

if [ "`id -u`" -eq 0 ]; then
    echo "Running as root is not advised, please check the documentation on how to run as non-root user"
    USER_PERMISSIONS="-u 0:0"
else
    GROUPID=`id -g`
    USER_PERMISSIONS="-u $UID:$GROUPID"
fi

group_args=()
is_podman="$(docker --help | grep -o podman)"
if [ ! -z "$is_podman" ]; then
    group_args+=(--userns=keep-id)
fi

if [[ $(uname) == "Linux" ]]; then
  readlink_command="readlink -f"
elif [[ $(uname) == "Darwin" ]]; then
  readlink_command="realpath "
fi

function usage {
  __usage="Usage: $(basename $0) [-h] [--version] [-e] [-d Prometheus data-dir] [-L resolve the servers from the manager running on the given address] [-G path to grafana data-dir] [-s scylla-target-file] [-n node-target-file] [-l] [-v comma separated versions] [-j additional dashboard to load to Grafana, multiple params are supported] [-c grafana environment variable, multiple params are supported] [-b Prometheus command line options] [-g grafana port ] [ -p prometheus port ] [-a admin password] [-m alertmanager port] [ -M scylla-manager version ] [-D encapsulate docker param] [-r alert-manager-config] [-R prometheus-alert-file] [-N manager target file] [-A bind-to-ip-address] [-C alertmanager commands] [-Q Grafana anonymous role (Admin/Editor/Viewer)] [-S start with a system specific dashboard set] [-T additional-prometheus-targets] [--no-loki] [--no-alertmanager] [--loki-port port] [--promtail-port port] [--auto-restart] [--no-renderer] [-f alertmanager-dir]

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
  --no-alertmanager              - If set, do not run the Alertmanager.
  --loki-port port               - If set, loki would use the given port number
  --promtail-port port           - If set, promtail would use the given port number
  --promtail-binary-port port    - If set, promtail would use the given port number for the binary protocol
  --no-cas                       - If set, Prometheus will drop all cas related metrics while scrapping
  --no-cdc                       - If set, Prometheus will drop all cdc related metrics while scrapping
  --auto-restart                 - If set, auto restarts the containers on failure.
  --no-renderer                  - If set, do not run the Grafana renderer container.
  --thanos-sc                    - If set, run thanos side car with the Prometheus server.
  --thanos                       - If set, run thanos query as a Grafana datasource.
  --enable-protobuf              - If set, enable the experimental Prometheus Protobuf with Native histograms support.
  --scrap [scrap duration]       - Change the default Prometheus scrap duration. Duration is in seconds.
  --target-directory             - If set, prometheus/targets/ directory will be set as a root directory for the target files
                                   the file names should be scylla_servers.yml, node_exporter_servers.yml, scylla_manager_agents.yml, and scylla_manager_servers.yml
  --stack id                     - Use this option when running a secondary stack, id could be 1-4
  --limit container,param        - Allow to set a specific Docker parameter for a container, where container can be:
                                   prometheus, grafana, alertmanager, loki, sidecar, grafanarender
  --archive  data-directory      - Treat data directory as an archive. This disables Prometheus time-to-live (infinite retention), and would run a minimal mode
The script starts Scylla Monitoring stack.
"
  echo "$__usage"
}

is_local () {
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
if [ -z "$BIND_ADDRESS_CONFIG" ]; then
  BIND_ADDRESS_CONFIG=""
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
if [ -z "$LOKI_PORT" ]; then
  LOKI_PORT=""
fi
LIMITS=""
VOLUMES=""
PARAMS=""
for arg; do
	if [ "$arg" = "--compose" ]; then
		echo "Using compose"
		exec ./make-compose.sh "$@"
	fi
done

for arg; do
    shift
    if [ -z "$LIMIT" ]; then
       case $arg in
            (--no-loki) RUN_LOKI=0
                ;;
            (--no-alertmanager) SKIP_ALERTMANAGER=1
                ;;
            (--loki-port)
                LIMIT="1"
                PARAM="loki-port"
                ;;
            (--promtail-port)
                LIMIT="1"
                PARAM="promtail-port"
                ;;
            (--promtail-binary-port)
                LIMIT="1"
                PARAM="promtail-binary-port"
                ;;
            (--no-renderer) RUN_RENDERER=""
                ;;
            (--thanos-sc) RUN_THANOS_SC=1
                ;;
            (--thanos) RUN_THANOS=1
                ;;
            (--auto-restart) DOCKER_PARAM="--restart=unless-stopped"
                ;;
            (--victoria-metrics) VICTORIA_METRICS="1"
                ;;
            (--auth)
                GRAFANA_ENV_COMMAND="$GRAFANA_ENV_COMMAND --auth"
                ;;
            (--disable-anonymous)
                GRAFANA_ENV_COMMAND="$GRAFANA_ENV_COMMAND --disable-anonymous"
                ;;
            (--enable-protobuf)
                PROMETHEUS_COMMAND_LINE_OPTIONS_ARRAY+=(--enable-feature=native-histograms)
                ;;
            (--alternator)
                RUN_ALTERNATOR="1"
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
                PARAM="param"
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
            (--stack)
                LIMIT="1"
                PARAM="stack"
                ;;
            (--scrap)
                LIMIT="1"
                PARAM="scrap"
                ;;
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
                ARCHIVE="1"
                LIMIT="1"
                PARAM="archive"
                ;;
            (*) set -- "$@" "$arg"
                ;;
        esac
    else
        DOCR=`echo $arg|cut -d',' -f1`
        VALUE=`echo $arg|cut -d',' -f2-|sed 's/#/ /g'`
        NOSPACE=`echo $arg|sed 's/ /#/g'`
        if [[ $NOSPACE == --* ]]; then
            echo "Error: No value given to --$PARAM"
            echo
            usage
            exit 1
        fi
        if [ "$PARAM" = "param" ]; then
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
        elif [ "$PARAM" = "loki-port" ]; then
            LOKI_PORT="$LOKI_PORT -p $NOSPACE"
            unset PARAM
        elif [ "$PARAM" = "promtail-port" ]; then
            LOKI_PORT="$LOKI_PORT -t $NOSPACE"
            unset PARAM
        elif [ "$PARAM" = "promtail-binary-port" ]; then
            LOKI_PORT="$LOKI_PORT -T $NOSPACE"
            unset PARAM
        elif [ "$PARAM" = "stack" ]; then
            STACK_ID="$NOSPACE"
            STACK_CMD="-s $NOSPACE"
            STACK="/stack/$NOSPACE"
            unset PARAM
        elif [ "$PARAM" = "scrap" ]; then
            SCRAP_CMD="--scrap $NOSPACE"
            unset PARAM
        elif [ "$PARAM" = "archive" ]; then
            DATA_DIR="$NOSPACE"
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

if [ ! -z $LIMIT ]; then
    echo "Error: No value given to --$PARAM"
    echo
    usage
    exit -1
fi
if [ "$DOCKER_PARAM" != "" ]; then
    DOCKER_PARAM_FROM_FILE="1"
fi
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
       BIND_ADDRESS_CONFIG="-A $OPTARG"
       ;;
    r) ALERT_MANAGER_RULE_CONFIG="-r $OPTARG"
       ;;
    R) if [[ -d "$OPTARG" ]]; then
        PROMETHEUS_RULES=$($readlink_command $OPTARG)":/etc/prometheus/prom_rules/"
       else
        PROMETHEUS_RULES=$($readlink_command $OPTARG)":/etc/prometheus/prometheus.rules.yml"
       fi
       ;;
    g) GRAFANA_PORT="-g $OPTARG"
       ;;
    m) ALERTMANAGER_PORT="-p $OPTARG"
       ;;
    T) PROMETHEUS_TARGETS="$PROMETHEUS_TARGETS -T $OPTARG"
       ;;
    Q) GRAFNA_ANONYMOUS_ROLE="-Q $OPTARG"
       ;;
    p) PROMETHEUS_PORT=$OPTARG
       ;;
    s) SCYLLA_TARGET_FILES=("$OPTARG")
       ;;
    n) NODE_TARGET_FILE=$OPTARG
       ;;
    l) if [[ "$DOCKER_PARAM" != *"--net=host"* ]]; then
        DOCKER_PARAM="$DOCKER_PARAM --net=host"
       fi
       ;;
    L) CONSUL_ADDRESS="-L $OPTARG"
       ;;
    P) LDAP_FILE="-P $OPTARG"
       ;;
    a) GRAFANA_ADMIN_PASSWORD="-a $OPTARG"
       ;;
    j) GRAFANA_DASHBOARD_ARRAY+=("$OPTARG")
       ;;
    c) GRAFANA_ENV_ARRAY+=("$OPTARG")
       ;;
    C) ALERTMANAGER_COMMANDS+=("$OPTARG")
       ;;
    D) if [ "$DOCKER_PARAM_FROM_FILE" = "1" ]; then
          DOCKER_PARAM=""
          DOCKER_PARAM_FROM_FILE=""
       fi
       DOCKER_PARAM="$DOCKER_PARAM $OPTARG"
       ;;
    b) PROMETHEUS_COMMAND_LINE_OPTIONS_ARRAY+=("$OPTARG")
       ;;
    N) SCYLLA_MANGER_TARGET_FILES=($OPTARG)
       ;;
    S) SPECIFIC_SOLUTION="-S $OPTARG"
       ;;
    E) RUN_RENDERER="-E"
       ;;
    f) ALERT_MANAGER_DIR="-f $OPTARG"
       ;;
    k) LOKI_DIR="-k $OPTARG"
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
if [ "$ARCHIVE" == "1" ]; then
    PROMETHEUS_COMMAND_LINE_OPTIONS_ARRAY+=(--storage.tsdb.retention.time=100y)
    RUN_LOKI=0
    SKIP_ALERTMANAGER="1"
    RUN_RENDERER=""
    CONSUL_ADDRESS="-L 127.0.0.1:0"
    if [ ! -d $DATA_DIR/ ]; then
        echo "The giving data directory $DATA_DIR does not exist"
        exit 1
    fi
    if [ -f $DATA_DIR/scylla.txt ]; then
        . $DATA_DIR/scylla.txt
        echo "Taking version from $DATA_DIR/scylla.txt"
        echo "Version set to $VERSIONS"
    else
        echo "scylla.txt not found in $DATA_DIR/. You can use it to start the monitoring stack with a given version"
        echo "For example, to start the monitoring stack with version 2014.1 and manager 3.3"
        echo 'echo VERSIONS="2024.1">'$DATA_DIR/scylla.txt
        echo 'echo MANAGER_VERSION="3.3">>'$DATA_DIR/scylla.txt
    fi
fi

if [ -z "$VERSIONS" ]; then
  echo "Scylla-version was not not found, add the -v command-line with a specific version (i.e. -v 2021.1)"
  exit 1
fi

if [ "$CURRENT_VERSION" = "master" ]; then
    if [ "$ARCHIVE" = "" ]; then
        echo ""
        echo "*****************************************************"
        echo "* WARNING: You are using the unstable master branch *"
        echo "* Check the README.md file for the stable releases  *"
        echo "*****************************************************"
        ./generate-dashboards.sh -v $VERSIONS -m $MANAGER_VERSION $STACK_CMD
    else
        echo ./generate-dashboards.sh -v $VERSIONS -F -R 0 -m $MANAGER_VERSION $STACK_CMD
        ./generate-dashboards.sh -v $VERSIONS -F -R 0 -m $MANAGER_VERSION $STACK_CMD
    fi
    echo "Generating the dashboards"

fi

if [[ $DOCKER_PARAM = *"--net=host"* ]]; then
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

    SCYLLA_TARGET_FILE="-v "$($readlink_command $SCYLLA_TARGET_FILE)":/etc/scylla.d/prometheus/targets/scylla_servers.yml"
    SCYLLA_MANGER_TARGET_FILE="-v "$($readlink_command $SCYLLA_MANGER_TARGET_FILE)":/etc/scylla.d/prometheus/targets/scylla_manager_servers.yml"
    NODE_TARGET_FILE="-v "$($readlink_command $NODE_TARGET_FILE)":/etc/scylla.d/prometheus/targets/node_exporter_servers.yml"
    SCYLLA_MANGER_AGENT_TARGET_FILE="-v "$($readlink_command $SCYLLA_MANGER_AGENT_TARGET_FILE)":/etc/scylla.d/prometheus/targets/scylla_manager_agents.yml"
else
    SCYLLA_TARGET_FILE=""
    SCYLLA_MANGER_TARGET_FILE=""
    SCYLLA_MANGER_AGENT_TARGET_FILE=""
    NODE_TARGET_FILE=""
fi

if [ "$TARGET_DIRECTORY" != "" ]; then
    SCYLLA_TARGET_FILE="-v "$($readlink_command $TARGET_DIRECTORY)":/etc/scylla.d/prometheus/targets/:z"
    if [ ! -f $TARGET_DIRECTORY/scylla_servers.yml ]; then
        echo "Warning, using $TARGET_DIRECTORY for Prometheus traget directory, scylla_servers.yml is missing, make sure to create it, or ScyllaDB targets will be missing"
    fi
    if [ ! -f $TARGET_DIRECTORY/node_exporter_servers.yml ]; then
        echo "Warning, using $TARGET_DIRECTORY for Prometheus traget directory, node_exporter_servers.yml is missing, make sure to create it, or node-exporter targets will be missing"
    fi
    if [ ! -f $TARGET_DIRECTORY/scylla_manager_agents.yml ]; then
        echo "Warning, using $TARGET_DIRECTORY for Prometheus traget directory, scylla_manager_agents.yml is missing, make sure to create it, or ScyllaDB manager-agent targets will be missing"
    fi
    if [ ! -f $TARGET_DIRECTORY/scylla_manager_servers.yml ]; then
        echo "Warning, using $TARGET_DIRECTORY for Prometheus traget directory, scylla_manager_servers.yml is missing, make sure to create it, or ScyllaDB manager target will be missing"
    fi
fi
if [ -z $DATA_DIR ]
then
    USER_PERMISSIONS=""
    echo "Warning: without an external Prometheus directory, Prometheus data will be deleted on shutdown, use the -d command line flag for data persistence."
else
    if [ -d $DATA_DIR ]; then
        echo "Loading prometheus data from $DATA_DIR"
    else
        echo "Creating data directory $DATA_DIR"
        mkdir -p $DATA_DIR
    fi
    if [[ "$VICTORIA_METRICS" = "1" ]]; then
        DATA_DIR_CMD="-v "$($readlink_command $DATA_DIR)":/victoria-metrics-data"
    else
        DATA_DIR_CMD="-v "$($readlink_command $DATA_DIR)":/prometheus/data:Z"
    fi
fi

if [ "$VERSIONS" = "latest" ]; then
    if [ -z "$BRANCH_VERSION" ] || [ "$BRANCH_VERSION" = "master" ]; then
        echo "Default versions (-v latest) is not supported on the master branch, use specific version instead"
        exit 1
    fi
    VERSIONS=${DEFAULT_VERSION[$BRANCH_VERSION]}
    echo "The use of -v latest is deprecated. Use a specific version instead."
else
    if [ "$VERSIONS" = "all" ]; then
        VERSIONS=$ALL
    fi
fi
if [ "$STACK_ID" != "" ]; then
    echo "Running a seconddary stack $STACK_ID"
    echo "Note that the following containers will not run: loki, promtail, grafana renderer"
    echo "to stop it use ./kill-all.sh --stack $STACK_ID"
    RUN_LOKI=0
    RUN_RENDERER=""
    PROMETHEUS_PORT=${STACK_PROMETHEUS["$STACK_ID"]}
    GRAFANA_PORT="-g"${STACK_GRAFANA["$STACK_ID"]}
    ALERTMANAGER_PORT="-p "${STACK_ALERTMANAGER["$STACK_ID"]}
fi

ALERTMANAGER_COMMAND=""
for val in "${ALERTMANAGER_COMMANDS[@]}"; do
    ALERTMANAGER_COMMAND="$ALERTMANAGER_COMMAND -C $val"
done

if [ "$SKIP_ALERTMANAGER" = "1" ]; then
    AM_ADDRESS="127.0.0.1:9093"
else
    echo "Wait for alert manager container to start"
    AM_ADDRESS=`./start-alertmanager.sh $ALERTMANAGER_PORT $ALERT_MANAGER_DIR -D "$DOCKER_PARAM" $LIMITS $VOLUMES $PARAMS $ALERTMANAGER_COMMAND $BIND_ADDRESS_CONFIG $ALERT_MANAGER_RULE_CONFIG`
    if [ $? -ne 0 ]; then
        echo "$AM_ADDRESS"
        exit 1
    fi
fi
LOKI_ADDRESS=""
if [ $RUN_LOKI -eq 1 ]; then
    echo "Wait for Loki container to start."
	LOKI_ADDRESS=`./start-loki.sh $BIND_ADDRESS_CONFIG $LOKI_DIR $LOKI_PORT -D "$DOCKER_PARAM" $LIMITS $VOLUMES $PARAMS -m $AM_ADDRESS`
	if [ $? -ne 0 ]; then
	    echo "$LOKI_ADDRESS"
	    exit 1
	fi
    LOKI_ADDRESS="-L $LOKI_ADDRESS"
fi

if [ -z $PROMETHEUS_PORT ]; then
    PROMETHEUS_PORT=9090
    PROMETHEUS_NAME=aprom
else
    PROMETHEUS_NAME=aprom-$PROMETHEUS_PORT
fi

docker container inspect $PROMETHEUS_NAME > /dev/null 2>&1
if [ $? -eq 0 ]; then
    printf "\nSome of the monitoring docker instances ($PROMETHEUS_NAME) exist. Make sure all containers are killed and removed. You can use kill-all.sh for that\n"
    exit 1
fi


# Exit if Docker engine is not running
if [ ! "$(docker ps)" ]
then
        echo "Error: Docker engine is not running"
        exit 1
fi

for val in "${PROMETHEUS_COMMAND_LINE_OPTIONS_ARRAY[@]}"; do
    if [[ $val = "--"* ]]; then
        PROMETHEUS_COMMAND_LINE_OPTIONS+=" $val"
    else
        echo "Using single hyphen is deprecated and will be removed in future version use -$val instead"
        PROMETHEUS_COMMAND_LINE_OPTIONS+=" -$val"
    fi
done

./prometheus-config.sh -m $AM_ADDRESS $STACK_CMD $SCRAP_CMD $CONSUL_ADDRESS $PROMETHEUS_TARGETS
if [ "$DATA_DIR" != "" ] && [ "$ARCHIVE" != "1" ]; then
    DATE=$(date +"%Y-%m-%d_%H_%M_%S")
    if [ -f $DATA_DIR/scylla.txt ]; then
        mv $DATA_DIR/scylla.txt $DATA_DIR/scylla.$DATE.txt
    fi
    echo LAST_COMMAND_LINE='"'"$@"'"' > $DATA_DIR/scylla.txt
    echo VERSIONS='"'"$VERSIONS"'"' >> $DATA_DIR/scylla.txt
    echo MANAGER_VERSION='"'"$MANAGER_VERSION"'"' >> $DATA_DIR/scylla.txt
    echo MONITORING_VERSION='"'"$CURRENT_VERSION"'"' >> $DATA_DIR/scylla.txt
    echo PROMETHEUS_VERSION='"'"$PROMETHEUS_VERSION"'"' >> $DATA_DIR/scylla.txt
    echo LAST_RUN='"'"$DATE"'"' >> $DATA_DIR/scylla.txt
    if [ "$RUN_ALTERNATOR" = "1" ]; then
        echo RUN_ALTERNATOR=1 >> $DATA_DIR/scylla.txt
    fi
fi
if [ -z $HOST_NETWORK ]; then
    PORT_MAPPING="-p $BIND_ADDRESS$PROMETHEUS_PORT:9090"
fi
if [[ "$VICTORIA_METRICS" = "1" ]]; then
    echo "Using victoria metrics"

    docker run -d --rm $DATA_DIR_CMD $PORT_MAPPING --name $PROMETHEUS_NAME \
    -v $PWD/prometheus/build/prometheus.yml:/etc/promscrape.config.yml:z \
    $SCYLLA_TARGET_FILE \
     $SCYLLA_MANGER_TARGET_FILE \
     $NODE_TARGET_FILE \
     $SCYLLA_MANGER_AGENT_TARGET_FILE \
    victoriametrics/victoria-metrics:$VICTORIA_METRICS_VERSION $PROMETHEUS_COMMAND_LINE_OPTIONS \
     ${DOCKER_PARAMS["prometheus"]} -promscrape.config=/etc/promscrape.config.yml -promscrape.config.strictParse=false -httpListenAddr=:9090
else
docker run -d $DOCKER_PARAM ${DOCKER_LIMITS["prometheus"]} $USER_PERMISSIONS \
     $DATA_DIR_CMD \
     "${group_args[@]}" \
     -v $PWD/prometheus/build$STACK/prometheus.yml:/etc/prometheus/prometheus.yml:z \
     -v $PROMETHEUS_RULES:z \
     $SCYLLA_TARGET_FILE \
     $SCYLLA_MANGER_TARGET_FILE \
     $NODE_TARGET_FILE \
     $SCYLLA_MANGER_AGENT_TARGET_FILE \
     $PORT_MAPPING --name $PROMETHEUS_NAME docker.io/prom/prometheus:$PROMETHEUS_VERSION \
     --web.enable-lifecycle --config.file=/etc/prometheus/prometheus.yml $PROMETHEUS_COMMAND_LINE_OPTIONS \
     ${DOCKER_PARAMS["prometheus"]}
fi

if [ $? -ne 0 ]; then
    echo "Error: Prometheus container failed to start"
    echo "For more information use: docker logs $PROMETHEUS_NAME"
    exit 1
fi

# Number of retries waiting for a Docker container to start
RETRIES=7

# Wait till Prometheus is available
printf "Wait for Prometheus container to start."
TRIES=0
until $(curl --output /dev/null -f --silent http://localhost:$PROMETHEUS_PORT) || [ $TRIES -eq $RETRIES ]; do
    printf '.'
    ((TRIES=TRIES+1))
    sleep 5
done
echo

if [ ! "$(docker ps -q -f name=$PROMETHEUS_NAME)" ]
then
        echo "Error: Prometheus container failed to start"
        echo "For more information use: docker logs $PROMETHEUS_NAME"
        exit 1
fi

# Can't use localhost here, because the monitoring may be running remotely.
# Also note that the port to which we need to connect is 9090, regardless of which port we bind to at localhost.
DB_ADDRESS="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $PROMETHEUS_NAME):9090"

if [ "$DB_ADDRESS" = ":9090" ]; then
    if [[ $(uname) == "Linux" ]]; then
        HOST_IP=$(hostname -I | awk '{print $1}')
    elif [[ $(uname) == "Darwin" ]]; then
        HOST_IP=$(ifconfig en0 | awk '/inet / {print $2}')
    fi
    DB_ADDRESS="$HOST_IP:$PROMETHEUS_PORT"
fi

if [[ "$VICTORIA_METRICS" = "1" ]]; then
     echo "running vmalert"

     docker run -d \
     --name vmalert \
     -v $PROMETHEUS_RULES:z \
     victoriametrics/vmalert:$VICTORIA_METRICS_VERSION -rule=/etc/prometheus/prom_rules/*yml \
    -datasource.url=http://$DB_ADDRESS \
    -notifier.url=http://$AM_ADDRESS \
    -notifier.url=http://$AM_ADDRESS \
    -remoteWrite.url=http://$DB_ADDRESS \
    -remoteRead.url=http://$DB_ADDRESS
fi
if [ $RUN_THANOS_SC -eq 1 ]; then
    if [ -z $DATA_DIR ]; then
        echo "You must use external prometheus directory to use the thanos side cart"
    else
        ./start-thanos-sc.sh -d $DATA_DIR -D "$DOCKER_PARAM" -a $DB_ADDRESS $LIMITS $VOLUMES $PARAMS $BIND_ADDRESS_CONFIG
    fi
fi

if [ $RUN_THANOS -eq 1 ]; then
    ./start-thanos.sh -D "$DOCKER_PARAM" $BIND_ADDRESS_CONFIG
fi

for val in "${GRAFANA_ENV_ARRAY[@]}"; do
        GRAFANA_ENV_COMMAND="$GRAFANA_ENV_COMMAND -c $val"
done

for val in "${GRAFANA_DASHBOARD_ARRAY[@]}"; do
        GRAFANA_DASHBOARD_COMMAND="$GRAFANA_DASHBOARD_COMMAND -j $val"
done
if [ ! -z "$DATDOGPARAM" ]; then
   ./start-datadog.sh $DATDOGPARAM -p $DB_ADDRESS
fi
if [ "$RUN_ALTERNATOR" = 1 ]; then
    GRAFANA_ENV_COMMAND="$GRAFANA_ENV_COMMAND --alternator"
fi
./start-grafana.sh $SCRAP_CMD $LDAP_FILE $LOKI_ADDRESS $LIMITS $VOLUMES $PARAMS $BIND_ADDRESS_CONFIG $RUN_RENDERER $SPECIFIC_SOLUTION -p $DB_ADDRESS $GRAFNA_ANONYMOUS_ROLE -D "$DOCKER_PARAM" $GRAFANA_PORT $EXTERNAL_VOLUME -m $AM_ADDRESS -M $MANAGER_VERSION -v $VERSIONS $GRAFANA_ENV_COMMAND $GRAFANA_DASHBOARD_COMMAND $GRAFANA_ADMIN_PASSWORD $STACK_CMD
