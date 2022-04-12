#!/bin/bash -e

mkdir -p /var/lib/grafana/provisioning/
if [ ! -d "/var/lib/grafana/provisioning/dashboards/" ]; then
    echo "No dashboard directory, creating"
    cd /
    /generate-dashboards.sh -t $SPECIFIC_SOLUTION -v $VERSIONS -M $MANAGER_VERSION $GRAFANA_DASHBOARD_COMMAND -B /var/lib/grafana/provisioning/dashboards/
fi
VERSION=`echo $VERSIONS|cut -d',' -f1`
if [ -z "$GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH" ]; then
    export GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH="/var/lib/grafana/dashboards/ver_${VERSION}/scylla-overview.${VERSION}.json"
fi



if [ -z "$UA_ANALTYICS" ]; then
  . /var/lib/grafana/ua/UA.sh
fi
if [ -z "$GF_ANALYTICS_GOOGLE_ANALYTICS_UA_ID" ]; then
    export GF_ANALYTICS_GOOGLE_ANALYTICS_UA_ID="$UA_ANALTYICS"
fi
if [ ! -z "$COMPOSE_DATASOURCE" ]; then
    mkdir -p /var/lib/grafana/provisioning/datasources
    cp -r /var/lib/grafana/compose-datasources/* /var/lib/grafana/provisioning/datasources
fi
/run.sh