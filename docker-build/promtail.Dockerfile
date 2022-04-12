ARG PROMTAIL_VERSION="latest"
FROM docker.io/grafana/promtail:${PROMTAIL_VERSION}

ARG CURRENT_DIR="./docker-build"
ENV LOKI_ADDRESS="loki:3100"

COPY loki/promtail/promtail_config.template.yml /etc/promtail/promtail_config.template.yml
COPY $CURRENT_DIR/promtailinit.sh /promtailinit.sh
ENTRYPOINT ["/promtailinit.sh" ]
