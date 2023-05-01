#!/usr/bin/env bash

CURRENT_VERSION="master"
if [ -f CURRENT_VERSION.sh ]; then
    CURRENT_VERSION=`cat CURRENT_VERSION.sh`
fi

. versions.sh
VERSION_FOR_DEFAULTS=$CURRENT_VERSION
BRANCH_VERSION=`echo $CURRENT_VERSION|cut -d'.' -f1,2`
if [ -z ${DEFAULT_VERSION[$CURRENT_VERSION]} ]; then
    VERSION_FOR_DEFAULTS=$BRANCH_VERSION
fi
MANAGER_VERSION=${MANAGER_DEFAULT_VERSION[$VERSION_FOR_DEFAULTS]}
if [ "$1" = "-e" ]; then
    DEFAULT_VERSION=${DEFAULT_ENTERPRISE_VERSION[$VERSION_FOR_DEFAULTS]}
fi

. dashboards.sh

FORMAT_COMAND=""
FORCEUPDATE=""
SPECIFIC_SOLUTION=""
PRODUCTS=()
if [ -f env.sh ]; then
    . env.sh
fi

usage="$(basename "$0") [-h] [-v comma separated versions ]  [-D] [-j additional dashboard to load to Grafana, multiple params are supported] [-M scylla-manager version ] [-t] [-F force update] [-S start with a system specific dashboard set] -- Generates the grafana dashboards and their load files"
BASE_DASHBOARD_DIR="grafana/provisioning/dashboards"
while getopts ':htDv:j:M:S:B:P:F' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    t) TEST_ONLY=1
       ;;
    v) VERSIONS=$OPTARG
       FORMAT_COMAND="$FORMAT_COMAND -v $OPTARG"
       ;;
    M) MANAGER_VERSION=$OPTARG
       FORMAT_COMAND="$FORMAT_COMAND -M $OPTARG"
       ;;
    F) FORCEUPDATE="1"
       ;;
    P) PRODUCTS+=(-P)
       PRODUCTS+=($OPTARG)
       ;;
    S) SPECIFIC_SOLUTION="$OPTARG"
       ;;
    D) VERSIONS=${SUPPORTED_VERSIONS[$BRANCH_VERSION]}
       FORMAT_COMAND="$FORMAT_COMAND -v $VERSIONS"
       MANAGER_VERSION=${MANAGER_SUPPORTED_VERSIONS[$BRANCH_VERSION]}
       ;;
    B) BASE_DASHBOARD_DIR=$OPTARG
       ;;
    j) GRAFANA_DASHBOARD_ARRAY+=("$OPTARG")
       FORMAT_COMAND="$FORMAT_COMAND -j $OPTARG"
       ;;
  esac
done
if [[ -z "$TEST_ONLY" ]]; then
    mkdir -p grafana/build
fi

mkdir -p $BASE_DASHBOARD_DIR
rm -f $BASE_DASHBOARD_DIR/load.*.yaml

function set_loader {
    sed "s/NAME/$1/" grafana/load.yaml | sed "s/FOLDER/$2/" | sed "s/VERSION/$3/" > "$BASE_DASHBOARD_DIR/load.$1.yaml"
}

IFS=',' ;for v in $VERSIONS; do

if [ $v = "latest" ]; then
    if [ -z "$BRANCH_VERSION" ] || [ "$BRANCH_VERSION" = "master" ]; then
        echo "Default versions (-v latest) is not supported on the master branch, use specific version instead"
        exit 1
    fi
    v=${DEFAULT_VERSION[$BRANCH_VERSION]}
    echo "The use of -v latest is deprecated. Use a specific version instead."
fi
if [[ -z "$SPECIFIC_SOLUTION" ]]; then
    VERDIR_NAME="ver_$v"
else
    VERDIR_NAME=$SPECIFIC_SOLUTION"_$v"
fi

VERDIR="grafana/build/$VERDIR_NAME"
if [[ -z "$TEST_ONLY" ]]; then
   mkdir -p $VERDIR
fi

if [[ $VERSIONS = *","* ]]; then
    set_loader $v "$v" "$VERDIR_NAME"
else
    set_loader $v "" "$VERDIR_NAME"
fi

    for f in "${DASHBOARDS[@]}"; do
        if [ -e grafana/$f.template.json ]
        then
            if [ ! -f "$VERDIR/$f.$v.json" ] || [ "$VERDIR/$f.$v.json" -ot "grafana/$f.template.json" ] || [ ! -z "$FORCEUPDATE" ]; then
                if [[ -z "$TEST_ONLY" ]]; then
                    echo "updating dashboard grafana/$f.$v.template.json"
                   ./make_dashboards.py ${PRODUCTS[@]} -af $VERDIR -t grafana/types.json -d grafana/$f.template.json -R "__MONITOR_VERSION__=$CURRENT_VERSION"  -R "__SCYLLA_VERSION_DOT__=$v" -R "__MONITOR_BRANCH_VERSION=$BRANCH_VERSION" --replace-file docs/source/reference/metrics.yaml -V $v
               fi
            fi
        else
            if [ -f grafana/$f.$v.json ]
            then
                cp grafana/$f.$v.json $VERDIR
            fi
        fi
    done
done

IFS=',' ;for v in $MANAGER_VERSION; do
if [ -e grafana/scylla-manager.template.json ]
then
    VERDIR="grafana/build/manager_$v"
    mkdir -p $VERDIR
    set_loader "manager_$v" "" "manager_$v"
    if [ ! -f "$VERDIR/scylla-manager.$v.json" ] || [ "$VERDIR/scylla-manager.$v.json" -ot "grafana/scylla-manager.template.json" ] || [ "$VERDIR/scylla-manager.$v.json" -ot "grafana/types.json" ] || [ ! -z "$FORCEUPDATE" ]; then
        if [[ -z "$TEST_ONLY" ]]; then
           echo "updating grafana/scylla-manager.$v.template.json"
           ./make_dashboards.py ${PRODUCTS[@]}  -af $VERDIR -t grafana/types.json -d grafana/scylla-manager.template.json -R "__MONITOR_VERSION__=$CURRENT_VERSION" -R "__SCYLLA_VERSION_DOT__=$v" -R "__MONITOR_BRANCH_VERSION=$BRANCH_VERSION" --replace-file docs/source/reference/metrics.yaml -V $v
        else
           echo "notice: grafana/scylla-manager.template.json was updated, run ./generate-dashboards.sh $FORMAT_COMAND"
        fi
    fi
fi
done

for val in "${GRAFANA_DASHBOARD_ARRAY[@]}"; do
    VERDIR="grafana/build/default"
    set_loader "default" "" "default"
    mkdir -p $VERDIR
    if [[ $val == *".template.json" ]]; then
        val1=${val::-14}
        val1=${val1:8}
        if [ ! -f $VERDIR/$val1.json ] || [ $VERDIR/$val1.json -ot $val ] || [ ! -z "$FORCEUPDATE" ]; then
            if [[ -z "$TEST_ONLY" ]]; then
                echo "updating $val"
               ./make_dashboards.py ${PRODUCTS[@]} -af $VERDIR -t grafana/types.json -d $val -R "__MONITOR_VERSION__=$CURRENT_VERSION" -R "__MONITOR_BRANCH_VERSION=$BRANCH_VERSION" --replace-file docs/source/reference/metrics.yaml
            fi
        fi
    else
       cp $val $VERDIR
    fi
done

