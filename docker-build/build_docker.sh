#!/usr/bin/env bash

CURRENT_VERSION="master"
DOCKER_REPO="scylladb"

. versions.sh
if [ -f  env.sh ]; then
    . env.sh
fi

if [ -f CURRENT_VERSION.sh ]; then
    CURRENT_VERSION=`cat CURRENT_VERSION.sh`
fi

if [ -z "$BRANCH_VERSION" ]; then
  BRANCH_VERSION=$CURRENT_VERSION
fi
if [ -z ${DEFAULT_VERSION[$CURRENT_VERSION]} ]; then
    BRANCH_VERSION=`echo $CURRENT_VERSION|cut -d'.' -f1,2`
fi
if [ -z "$MANAGER_VERSION" ];then
  MANAGER_VERSION=${MANAGER_DEFAULT_VERSION[$BRANCH_VERSION]}
fi
if [ -z "$VERSIONS" ]; then
  VERSIONS=${DEFAULT_ENTERPRISE_VERSION[$BRANCH_VERSION]}
fi

docker build -t $DOCKER_REPO/grafana:$CURRENT_VERSION . -f docker-build/grafana.Dockerfile --build-arg  CURRENT_DIR="./docker-build" \
--build-arg GRAFANA_VERSION="$GRAFANA_VERSION" \
--build-arg DEFAULT_VERSION="$VERSIONS" \
--build-arg MANAGER_VERSION=$MANAGER_VERSION \

docker build -t $DOCKER_REPO/loki:$CURRENT_VERSION . -f docker-build/loki.Dockerfile --build-arg  CURRENT_DIR="./docker-build" \
--build-arg LOKI_VERSION="$LOKI_VERSION"

docker build -t $DOCKER_REPO/promtail:$CURRENT_VERSION . -f docker-build/promtail.Dockerfile --build-arg  CURRENT_DIR="./docker-build" \
--build-arg PROMTAIL_VERSION="$LOKI_VERSION"

docker build -t $DOCKER_REPO/prometheus:$CURRENT_VERSION . -f docker-build/prometheus.Dockerfile --build-arg  CURRENT_DIR="./docker-build" \
--build-arg PROMETHEUS_VERSION="$PROMETHEUS_VERSION"

docker build -t $DOCKER_REPO/alertmanager:$CURRENT_VERSION . -f docker-build/alertmanager.Dockerfile --build-arg  CURRENT_DIR="./docker-build" \
--build-arg ALERTMANAGER_VERSION="$ALERT_MANAGER_VERSION"
