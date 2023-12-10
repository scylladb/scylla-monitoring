#!/bin/sh -e
echo "running loki init"

if [ -f /mnt/config/loki-config.yaml ]; then
    echo "Config exists loki-config.yaml"
else
    echo "Setting loki-config.yaml"
    sed "s/ALERTMANAGER/$ALERT_MANAGER_ADDRESS/" /mnt/config/loki-config.template.yaml > /mnt/config/loki-config.yaml
fi
/usr/bin/loki --config.file=/mnt/config/loki-config.yaml --ingester.wal-enabled=false
