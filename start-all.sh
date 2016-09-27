#!/usr/bin/env bash

sudo docker run -d -v $PWD/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:Z -p 9090:9090 --name aprom prom/prometheus:v1.0.0

sudo docker run -d -v $PWD/grafana/dashboards:/var/lib/grafana/dashboards:Z -i -p 3000:3000 \
     -e "GF_AUTH_BASIC_ENABLED=false" \
     -e "GF_AUTH_ANONYMOUS_ENABLED=true" \
     -e "GF_AUTH_ANONYMOUS_ORG_ROLE=Admin" \
     -e "GF_INSTALL_PLUGINS=grafana-piechart-panel" \
     -e "GF_DASHBOARDS_JSON_ENABLED=TRUE" \
     -e "GF_DASHBOARDS_JSON_PATH=/var/lib/grafana/dashboards" \
     --name agraf grafana/grafana:3.1.0

# Wait till Grafana API
until $(curl --output /dev/null -f --silent http://localhost:3000/api/org); do
    printf '.'
    sleep 5
done

DB_IP="$(sudo docker inspect --format '{{ .NetworkSettings.IPAddress }}' aprom)"

curl -XPOST -i http://localhost:3000/api/datasources \
     --data-binary '{"name":"prometheus", "type":"prometheus", "url":"'"http://$DB_IP:9090"'", "access":"proxy", "basicAuth":false}' \
     -H "Content-Type: application/json"
