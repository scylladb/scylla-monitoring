#!/usr/bin/env bash

. versions.sh
VERSIONS=$DEFAULT_VERSION

usage="$(basename "$0") [-h] [-v comma separated versions ]  [-j additional dashboard to load to Grafana, multiple params are supported] [-M scylla-manager version ] -- Generates the grafana dashboards and their load files"

while getopts ':hv:j:M:' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    v) VERSIONS=$OPTARG
       ;;
    M) MANAGER_VERSION=$OPTARG
       ;;
    j) GRAFANA_DASHBOARD_ARRAY+=("$OPTARG")
       ;;
  esac
done

function set_loader {
    sed "s/NAME/$1/" grafana/load.yaml | sed "s/FOLDER/$2/" | sed "s/VERSION/$3/" > "grafana/provisioning/dashboards/load.$1.yaml"
}

mkdir -p grafana/build
rm -f grafana/build/load.*.yml
IFS=',' ;for v in $VERSIONS; do
VERDIR="grafana/build/ver_$v"
mkdir -p $VERDIR
set_loader $v $v "ver_$v"
for f in scylla-dash scylla-dash-per-server scylla-dash-io-per-server scylla-dash-cpu-per-server scylla-dash-per-machine; do
    if [ -e grafana/$f.$v.template.json ]
    then
        if [ ! -f "$VERDIR/$f.$v.json" ] || [ "$VERDIR/$f.$v.json" -ot "grafana/$f.$v.template.json" ]; then
            ./make_dashboards.py -af $VERDIR -t grafana/types.json -d grafana/$f.$v.template.json
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
    if [ ! -f "$VERDIR/scylla-manager.$MANAGER_VERSION.json" ] || [ "$VERDIR/scylla-manager.$MANAGER_VERSION.json" -ot "grafana/scylla-manager.$MANAGER_VERSION.template.json" ]; then
        ./make_dashboards.py -af $VERDIR -t grafana/types.json -d grafana/scylla-manager.$MANAGER_VERSION.template.json
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
           ./make_dashboards.py -af $VERDIR -t grafana/types.json -d $val
        fi
    else
       cp $val $VERDIR
    fi
done

