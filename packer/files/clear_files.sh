#!/usr/bin/env bash

BASE=`dirname "$(readlink -f "$0")"`
echo "clearing $BASE/scylla-grafana-monitoring-scylla-monitoring/grafana/build/*/$1.*.json"
for FILE in $BASE/scylla-grafana-monitoring-scylla-monitoring/grafana/build/ver_*/$1.*.json; do
  rm -f "$FILE"
done
