#!/usr/bin/env bash

. versions.sh
VERSIONS=$DEFAULT_VERSION
GRAFANA_PORT=3000
DB_ADDRESS="127.0.0.1:9090"

usage="$(basename "$0") [-h] [-v comma separated versions ] [-g grafana port ] [-p ip:port address of prometheus ] [-a admin password] [-j additional dashboard to load to Grafana, multiple params are supported] -- loads the prometheus datasource and the Scylla dashboards into an existing grafana installation"

while getopts ':hg:p:v:a:j:' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    v) VERSIONS=$OPTARG
       ;;
    g) GRAFANA_PORT=$OPTARG
       ;;
    j) GRAFANA_DASHBOARD_ARRAY+=("$OPTARG")
       ;;
    p) DB_ADDRESS=$OPTARG
       ;;
    a) GRAFANA_ADMIN_PASSWORD=$OPTARG
       ;;
  esac
done

curl -XPOST -i http://admin:$GRAFANA_ADMIN_PASSWORD@localhost:$GRAFANA_PORT/api/datasources \
     --data-binary '{"name":"prometheus", "type":"prometheus", "url":"'"http://$DB_ADDRESS"'", "access":"proxy", "basicAuth":false}' \
     -H "Content-Type: application/json"

mkdir -p grafana/build
IFS=',' ;for v in $VERSIONS; do
for f in scylla-dash scylla-dash-per-server scylla-dash-io-per-server; do
	if [ -e grafana/$f.$v.template.json ]
	then
		./make_dashboards.py -t grafana/types.json -d grafana/$f.$v.template.json
		curl -XPOST -i http://admin:$GRAFANA_ADMIN_PASSWORD@localhost:$GRAFANA_PORT/api/dashboards/db --data-binary @./grafana/build/$f.$v.json -H "Content-Type: application/json"
  else
    curl -XPOST -i http://admin:$GRAFANA_ADMIN_PASSWORD@localhost:$GRAFANA_PORT/api/dashboards/db --data-binary @./grafana/$f.$v.json -H "Content-Type: application/json"  
	fi
	
done
done

for val in "${GRAFANA_DASHBOARD_ARRAY[@]}"; do
        curl -XPOST -i http://admin:$GRAFANA_ADMIN_PASSWORD@localhost:$GRAFANA_PORT/api/dashboards/db --data-binary @$val -H "Content-Type: application/json"
done
