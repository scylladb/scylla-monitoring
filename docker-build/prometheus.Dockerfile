ARG PROMETHEUS_VERSION="latest"
FROM docker.io/prom/prometheus:${PROMETHEUS_VERSION}

USER       nobody

ENV ALERT_MANAGER_ADDRESS="aalert:9093" CONSUL_ADDRESS="" PROMETHEUS_TARGETS=""
ARG CURRENT_DIR="./docker-build"
COPY --chown=nobody:nobody  prometheus/prom_rules /etc/prometheus/prom_rules/
COPY --chown=nobody:nobody  $CURRENT_DIR/prometheusinit.sh /prometheusinit.sh
COPY --chown=nobody:nobody  prometheus/prometheus.yml.template /etc/prometheus/conf/prometheus.yml.template
COPY --chown=nobody:nobody  prometheus/prometheus.consul.yml.template /etc/prometheus/conf/prometheus.consul.yml.template
ENTRYPOINT ["/prometheusinit.sh" ]
