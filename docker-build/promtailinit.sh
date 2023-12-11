#!/bin/sh -e
echo "running promtail init"

if [ -f /etc/promtail/config.yml ]; then
    echo "Config exists promtail-config.yaml"
else
    echo "Setting promtail-config.yaml"
    sed "s/ALERTMANAGER/$ALERT_MANAGER_ADDRESS/" /etc/promtail/promtail-config.template.yaml > /etc/promtail/config.yml
fi
/usr/bin/promtail --config.file=/etc/promtail/config.yml /etc/promtail/config.yml
