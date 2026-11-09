RUN_THANOS_SC=1
RUN_LOCAL_THANOS=1
# The config watcher (scylla_monitoring_config.py): seconds between checks of
# its config file, and, on a fresh instance, reading the stack's images and
# code from disk while it waits for the first file
WATCHER_POLL_INTERVAL=5
WARM_ON_BOOT=1
# Grafana uses the plugins the image build installed, and fetches none at
# start; the build sets it to false to install them
PLUGINS_PREINSTALL_DISABLED=${PLUGINS_PREINSTALL_DISABLED:-true}
