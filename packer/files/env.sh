RUN_THANOS_SC=1
RUN_LOCAL_THANOS=1
# The config watcher (scylla_monitoring_config.py): seconds between checks of
# its config file
WATCHER_POLL_INTERVAL=5
# Grafana installs no plugin at start, so grafana/plugins holds only the ones
# monitoring ships; Grafana's own plugins load from its image
PLUGINS_PREINSTALL_DISABLED=${PLUGINS_PREINSTALL_DISABLED:-true}
