#!/usr/bin/env bash

. versions.sh
VERSIONS=$DEFAULT_VERSION
GRAFANA_PORT=3000
DB_ADDRESS="127.0.0.1:9090"

while getopts 'g:p:v:' option; do
  case "$option" in
    v) VERSIONS=$OPTARG
       ;;
    g) GRAFANA_PORT=$OPTARG
       ;;
    p) DB_ADDRESS=$OPTARG
       ;;
  esac
done

curl -XPOST -i http://localhost:$GRAFANA_PORT/api/datasources \
     --data-binary '{"name":"prometheus", "type":"prometheus", "url":"'"http://$DB_ADDRESS"'", "access":"proxy", "basicAuth":false}' \
     -H "Content-Type: application/json"
IFS=',' ;for v in $VERSIONS; do
	curl -XPOST -i http://localhost:$GRAFANA_PORT/api/dashboards/db --data-binary @./grafana/scylla-dash.$v.json -H "Content-Type: application/json"
	curl -XPOST -i http://localhost:$GRAFANA_PORT/api/dashboards/db --data-binary @./grafana/scylla-dash-per-server.$v.json -H "Content-Type: application/json"
	curl -XPOST -i http://localhost:$GRAFANA_PORT/api/dashboards/db --data-binary @./grafana/scylla-dash-io-per-server.$v.json -H "Content-Type: application/json"
done

