ARG LOKI_VERSION="latest"
FROM docker.io/grafana/loki:${LOKI_VERSION}

ARG GF_GID="10001"

USER root
RUN mkdir -p /data/loki
RUN chown 10001:10001 /data/loki

USER loki
ENV ALERT_MANAGER_ADDRESS="aalert:9093"
ARG CURRENT_DIR="./docker-build"
COPY --chown=loki:${GF_GID} loki/rules/scylla /etc/loki/rules/fake/
COPY --chown=loki:${GF_GID} loki/conf /mnt/config/
COPY --chown=loki:${GF_GID}  $CURRENT_DIR/lokiinit.sh /lokiinit.sh
ENTRYPOINT ["/lokiinit.sh" ]
