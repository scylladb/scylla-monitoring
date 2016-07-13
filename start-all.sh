#!/usr/bin/env bash

DB_IP=$1

sudo docker run -d -v $PWD/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml -p 9090:9090 prom/prometheus
sudo docker run -d -i -p 3000:3000 \
     -e "GF_AUTH_BASIC_ENABLED=false" \
     -e "GF_AUTH_ANONYMOUS_ENABLED=true" \
     -e "GF_AUTH_ANONYMOUS_ORG_ROLE=Admin" \
     -e "GF_INSTALL_PLUGINS=grafana-piechart-panel" \
     grafana/grafana:3.1.0

sleep 3
curl -XPOST -i http://localhost:3000/api/datasources \
     --data-binary '{"name":"prometheus", "type":"prometheus", "url":"'"http://$DB_IP:9090"'", "access":"proxy", "basicAuth":false}' \
     -H "Content-Type: application/json"
curl -XPOST -i http://localhost:3000/api/dashboards/db --data-binary @./grafana/scylla-dash.json -H "Content-Type: application/json"
curl -XPOST -i http://localhost:3000/api/dashboards/db --data-binary @./grafana/scylla-dash-per-server.json -H "Content-Type: application/json"
