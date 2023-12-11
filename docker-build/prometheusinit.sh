#!/bin/sh -e
echo "running prometheus init"
if [ -f /etc/prometheus/conf/prometheus.yml ]; then
    echo "Config exists /etc/prometheus/conf/prometheus.yml"
else
    echo "Setting prometheus.yml"
    DST="/etc/prometheus/conf/"
    SRC="/etc/prometheus/conf"
    mkdir -p $DST
    if [ -z $CONSUL_ADDRESS ]; then
        sed "s/AM_ADDRESS/$AM_ADDRESS/" $SRC/prometheus.yml.template > $DST/prometheus.yml
    else
        if [[ ! $CONSUL_ADDRESS = *":"* ]]; then
            CONSUL_ADDRESS="$CONSUL_ADDRESS:5090"
        fi
        sed "s/AM_ADDRESS/$AM_ADDRESS/" $SRC/prometheus.consul.yml.template| sed "s/MANAGER_ADDRESS/$CONSUL_ADDRESS/" > $DST/prometheus.yml
    fi
fi
echo "Starting prometheus"
/bin/prometheus --config.file=/etc/prometheus/conf/prometheus.yml --storage.tsdb.path=/prometheus \
             --web.console.libraries=/usr/share/prometheus/console_libraries \
             --web.console.templates=/usr/share/prometheus/consoles
