ARG GRAFANA_VERSION="latest"
FROM docker.io/grafana/grafana:${GRAFANA_VERSION}

ARG DEFAULT_VERSION="2021.1" GF_INSTALL_IMAGE_RENDERER_PLUGIN="false"
ENV VERSIONS=${DEFAULT_VERSION}

USER root

ARG GF_GID="0"
ENV GF_PATHS_PLUGINS="/var/lib/grafana-plugins"

RUN mkdir -p "$GF_PATHS_PLUGINS" && \
    chown -R grafana:${GF_GID} "$GF_PATHS_PLUGINS"

RUN if [ $GF_INSTALL_IMAGE_RENDERER_PLUGIN = "true" ]; then \
    echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories && \
    echo "http://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories && \
    echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories && \
    apk --no-cache  upgrade && \
    apk add --no-cache udev ttf-opensans chromium && \
    rm -rf /tmp/* && \
    rm -rf /usr/share/grafana/tools/phantomjs; \
fi

USER grafana

ENV GF_PLUGIN_RENDERING_CHROME_BIN="/usr/bin/chromium-browser"

RUN if [ $GF_INSTALL_IMAGE_RENDERER_PLUGIN = "true" ]; then \
    grafana-cli \
        --pluginsDir "$GF_PATHS_PLUGINS" \
        --pluginUrl https://github.com/grafana/grafana-image-renderer/releases/latest/download/plugin-linux-x64-glibc-no-chromium.zip \
        plugins install grafana-image-renderer; \
fi

ARG GF_INSTALL_PLUGINS=""

RUN grafana-cli --pluginsDir "${GF_PATHS_PLUGINS}" plugins install camptocamp-prometheus-alertmanager-datasource

ARG GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=scylladb-scylla-datasource
ENV GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=${GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS}

RUN if [ ! -z "${GF_INSTALL_PLUGINS}" ]; then \
    OLDIFS=$IFS; \
    IFS=','; \
    for plugin in ${GF_INSTALL_PLUGINS}; do \
        IFS=$OLDIFS; \
        if expr match "$plugin" '.*\;.*'; then \
            pluginUrl=$(echo "$plugin" | cut -d';' -f 1); \
            pluginInstallFolder=$(echo "$plugin" | cut -d';' -f 2); \
            grafana-cli --pluginUrl ${pluginUrl} --pluginsDir "${GF_PATHS_PLUGINS}" plugins install "${pluginInstallFolder}"; \
        else \
            grafana-cli --pluginsDir "${GF_PATHS_PLUGINS}" plugins install ${plugin}; \
        fi \
    done \
fi
COPY --chown=grafana:${GF_GID} grafana/plugins/scylla-plugin ${GF_PATHS_PLUGINS}/scylla-plugin/
ARG CURRENT_DIR="./docker-build"
COPY --chown=grafana:${GF_GID}  $CURRENT_DIR/grafanainit.sh /grafanainit.sh

ARG GRAFANA_AUTH=false
ENV GF_AUTH_BASIC_ENABLED=${GRAFANA_AUTH}
ARG GRAFANA_AUTH_ANONYMOUS=true
ENV GF_AUTH_ANONYMOUS_ENABLED=${GRAFANA_AUTH_ANONYMOUS}
ENV COMPOSE_DATASOURCE=""
ARG ANONYMOUS_ROLE="Admin"
ENV GF_AUTH_ANONYMOUS_ORG_ROLE=${ANONYMOUS_ROLE}
ARG GRAFANA_ADMIN_PASSWORD="admin"
ENV GF_PANELS_DISABLE_SANITIZE_HTML=true
ENV GF_PATHS_PROVISIONING=/var/lib/grafana/provisioning
ENV GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
COPY --chown=grafana:${GF_GID}  grafana/build /var/lib/grafana/dashboards/
RUN mkdir -p "/var/lib/grafana/provisioning/" && \
    chown -R grafana:${GF_GID} "/var/lib/grafana/provisioning/"
ARG SPECIFIC_SOLUTION=""
ENV SPECIFIC_SOLUTION=${SPECIFIC_SOLUTION}
ARG MANAGER_VERSION="2.6"
ENV MANAGER_VERSION=${MANAGER_VERSION}
ARG GRAFANA_DASHBOARD_COMMAND=""
ENV GRAFANA_DASHBOARD_COMMAND=${GRAFANA_DASHBOARD_COMMAND}
#ENV GF_RENDERING_SERVER_URL=http://localhost:8081/render
#ENV GF_RENDERING_CALLBACK_URL=http://localhost:3000/
COPY --chown=grafana:${GF_GID}  generate-dashboards.sh /generate-dashboards.sh
COPY --chown=grafana:${GF_GID}  versions.sh /versions.sh
COPY --chown=grafana:${GF_GID}  dashboards.sh /dashboards.sh
COPY --chown=grafana:${GF_GID}  CURRENT_VERSION.sh /CURRENT_VERSION.sh
COPY --chown=grafana:${GF_GID}  grafana/load.yaml /grafana/load.yaml
COPY --chown=grafana:${GF_GID}  UA.sh /var/lib/grafana/ua/UA.sh
COPY ./grafana/provisioning/compose-datasources /var/lib/grafana/compose-datasources/
ENTRYPOINT ["/grafanainit.sh" ]
