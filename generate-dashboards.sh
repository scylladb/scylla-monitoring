#!/usr/bin/env bash

. versions.sh
. dashboards.sh
VERSIONS=$DEFAULT_VERSION
if [ -f setenv.sh ]; then
    . setenv.sh
fi

FORMAT_COMAND=""
usage="$(basename "$0") [-h] [-v comma separated versions ]  [-j additional dashboard to load to Grafana, multiple params are supported] [-M scylla-manager version ] [-t] -- Generates the grafana dashboards and their load files"

while getopts ':htv:j:M:' option; do
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
    j) GRAFANA_DASHBOARD_ARRAY+=("$OPTARG")
       FORMAT_COMAND="$FORMAT_COMAND -j $OPTARG"
       ;;
  esac
done
if [[ -z "$TEST_ONLY" ]]; then
    mkdir -p grafana/build
fi

mkdir -p grafana/provisioning/dashboards
rm -f grafana/provisioning/dashboards/load.*.yaml

function set_loader {
    sed "s/NAME/$1/" grafana/load.yaml | sed "s/FOLDER/$2/" | sed "s/VERSION/$3/" > "grafana/provisioning/dashboards/load.$1.yaml"
}

IFS=',' ;for v in $VERSIONS; do
VERDIR="grafana/build/ver_$v"
if [[ -z "$TEST_ONLY" ]]; then
   mkdir -p $VERDIR
fi
set_loader $v $v "ver_$v"
for f in "${DASHBOARDS[@]}"; do
    if [ -e grafana/$f.$v.template.json ]
    then
        if [ ! -f "$VERDIR/$f.$v.json" ] || [ "$VERDIR/$f.$v.json" -ot "grafana/$f.$v.template.json" ]; then
            if [[ -z "$TEST_ONLY" ]]; then
                echo "updating dashboard grafana/$f.$v.template.json"
               ./make_dashboards.py -af $VERDIR -t grafana/types.json -d grafana/$f.$v.template.json
           else
               echo "notice: grafana/$f.$v.template.json was updated, run ./generate-dashboards.sh $FORMAT_COMAND"
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

if [ -e grafana/scylla-manager.$MANAGER_VERSION.template.json ]
then
    VERDIR="grafana/build/manager_$MANAGER_VERSION"
    mkdir -p $VERDIR
    set_loader "manager_$MANAGER_VERSION" "manager_$MANAGER_VERSION" "manager_$MANAGER_VERSION"
    if [ ! -f "$VERDIR/scylla-manager.$MANAGER_VERSION.json" ] || [ "$VERDIR/scylla-manager.$MANAGER_VERSION.json" -ot "grafana/scylla-manager.$MANAGER_VERSION.template.json" ] || [ "$VERDIR/scylla-manager.$MANAGER_VERSION.json" -ot "grafana/types.json" ]; then
        if [[ -z "$TEST_ONLY" ]]; then
           echo "updating grafana/scylla-manager.$MANAGER_VERSION.template.json"
           ./make_dashboards.py -af $VERDIR -t grafana/types.json -d grafana/scylla-manager.$MANAGER_VERSION.template.json
        else
           echo "notice: grafana/scylla-manager.$MANAGER_VERSION.template.json was updated, run ./generate-dashboards.sh $FORMAT_COMAND"
        fi
    fi
fi

for val in "${GRAFANA_DASHBOARD_ARRAY[@]}"; do
    VERDIR="grafana/build/default"
    set_loader "default" "" "default"
    mkdir -p $VERDIR
    if [[ $val == *".template.json" ]]; then
        val1=${val::-14}
        val1=${val1:8}
        if [ ! -f $VERDIR/$val1.json ] || [ $VERDIR/$val1.json -ot $val ]; then
            if [[ -z "$TEST_ONLY" ]]; then
                echo "updating $val"
               ./make_dashboards.py -af $VERDIR -t grafana/types.json -d $val
            else
                echo "notice: $val was updated, run ./generate-dashboards.sh $FORMAT_COMAND"
            fi
        fi
    else
       cp $val $VERDIR
    fi
done

