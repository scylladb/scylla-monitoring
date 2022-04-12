ARG ALERTMANAGER_VERSION="latest"
FROM docker.io/prom/alertmanager:${ALERTMANAGER_VERSION}

ARG CURRENT_DIR="./docker-build"

COPY ./prometheus/rule_config.yml /etc/alertmanager/config.yml