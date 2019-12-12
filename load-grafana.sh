#!/usr/bin/env bash

. versions.sh
. dashboards.sh

VERSIONS=$DEFAULT_VERSION
GRAFANA_HOST="localhost"
GRAFANA_PORT=3000
DB_ADDRESS="127.0.0.1:9090"

usage="$(basename "$0") [-h] [-v comma separated versions ] [-g grafana port ] [-H grafana hostname] [-m alert_manager ip:port] [-p ip:port address of prometheus ] [-a admin password] [-j additional dashboard to load to Grafana, multiple params are supported] [-M scylla-manager version ] -- loads the prometheus datasource and the Scylla dashboards into an existing grafana installation"

while getopts ':hg:H:p:v:a:j:m:M:' option; do
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
    H) GRAFANA_HOST=$OPTARG
       ;;
    j) GRAFANA_DASHBOARD_ARRAY+=("$OPTARG")
       ;;
    p) DB_ADDRESS=$OPTARG
       ;;
    m) AM_ADDRESS=$OPTARG
       ;;
    a) GRAFANA_ADMIN_PASSWORD=$OPTARG
       ;;
  esac
done

curl -XPOST -i http://admin:$GRAFANA_ADMIN_PASSWORD@$GRAFANA_HOST:$GRAFANA_PORT/api/datasources \
     --data-binary '{"name":"prometheus", "type":"prometheus", "url":"'"http://$DB_ADDRESS"'", "access":"proxy", "basicAuth":false}' \
     -H "Content-Type: application/json"

if [ -n $AM_ADDRESS ]
then
  curl -XPOST -i http://admin:$GRAFANA_ADMIN_PASSWORD@localhost:$GRAFANA_PORT/api/datasources \
       --data-binary '{"orgId":1,"name":"alertmanager", "type":"camptocamp-prometheus-alertmanager-datasource","typeLogoUrl":"public/img/icn-datasource.svg","access":"proxy","url":"'"http://$AM_ADDRESS"'","password":"","user":"","database":"","basicAuth":false,"isDefault":false,"jsonData":{"severity_critical": "4","severity_high": "3", "severity_warning": "2","severity_info": "1"}}' \
       -H "Content-Type: application/json"
fi

mkdir -p grafana/build
IFS=',' ;for v in $VERSIONS; do
for f in "${DASHBOARDS[@]}"; do
    if [ -e grafana/$f.$v.template.json ]
    then
        if [ ! -f "grafana/build/$f.$v.json" ] || [ "grafana/build/$f.$v.json" -ot "grafana/$f.$v.template.json" ]; then
            ./make_dashboards.py -t grafana/types.json -d grafana/$f.$v.template.json -R "__MONITOR_VERSION__=$CURRENT_VERSION"
        fi
        curl -XPOST -i http://admin:$GRAFANA_ADMIN_PASSWORD@$GRAFANA_HOST:$GRAFANA_PORT/api/dashboards/db --data-binary @./grafana/build/$f.$v.json -H "Content-Type: application/json"
    else
        if [ -f grafana/$f.$v.json ]
        then
            curl -XPOST -i http://admin:$GRAFANA_ADMIN_PASSWORD@$GRAFANA_HOST:$GRAFANA_PORT/api/dashboards/db --data-binary @./grafana/$f.$v.json -H "Content-Type: application/json"
        else
            printf "\nDashboard version $v, not found"
        fi
    fi
done
done

if [ -e grafana/scylla-manager.$MANAGER_VERSION.template.json ]
then
    if [ ! -f "grafana/build/scylla-manager.$MANAGER_VERSION.json" ] || [ "grafana/build/scylla-manager.$MANAGER_VERSION.json" -ot "grafana/scylla-manager.$MANAGER_VERSION.template.json" ]; then
        ./make_dashboards.py -t grafana/types.json -d grafana/scylla-manager.$MANAGER_VERSION.template.json
    fi
    curl -XPOST -i http://admin:$GRAFANA_ADMIN_PASSWORD@$GRAFANA_HOST:$GRAFANA_PORT/api/dashboards/db --data-binary @./grafana/build/scylla-manager.$MANAGER_VERSION.json -H "Content-Type: application/json"
fi

for val in "${GRAFANA_DASHBOARD_ARRAY[@]}"; do
    if [[ $val == *".template.json" ]]; then
        val1=${val::-14}
        val1=${val1:8}
        if [ ! -f "$val1.json" ] || [ "$val1.json" -ot "$val" ]; then
           ./make_dashboards.py -t grafana/types.json -d $val
        fi
        val="$val1.json"
    fi
    curl -XPOST -i http://admin:$GRAFANA_ADMIN_PASSWORD@$GRAFANA_HOST:$GRAFANA_PORT/api/dashboards/db --data-binary @./grafana/build/$val -H "Content-Type: application/json"
done
