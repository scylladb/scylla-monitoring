RUN_THANOS_SC=1
RUN_LOCAL_THANOS=1
# The config watcher (scylla_monitoring_config.py): seconds between checks of
# its config file
WATCHER_POLL_INTERVAL=5
# Grafana settings: the start scripts pass every GF_* variable to Grafana.
# Grafana installs no plugin at start, so grafana/plugins holds only the ones
# monitoring ships, and loads none of the data sources the dashboards do not use.
GF_PLUGINS_PREINSTALL_DISABLED=${GF_PLUGINS_PREINSTALL_DISABLED:-true}
GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=${GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS:-scylladb-scylla-datasource}
GF_PLUGINS_DISABLE_PLUGINS=${GF_PLUGINS_DISABLE_PLUGINS:-cloudwatch,elasticsearch,mssql,grafana-postgresql-datasource,influxdb,mysql,grafana-pyroscope-datasource,stackdriver,zipkin,opentsdb,jaeger,tempo}
