#!/usr/bin/env bash
usage="$(basename "$0") [-h] [-p ip:port address of prometheus ] [-m alert_manager address] [-L loki address] [--compose] -- Generate grafna's datasource file"

if [ "$1" = "" ]; then
    echo "$usage"
    exit
fi

if [ "$1" = "--compose" ]; then
    DB_ADDRESS="aprom:9090"
    ALERT_MANAGER_ADDRESS="aalert:9093"
    LOKI_ADDRESS="loki:3100"
else
    while getopts ':hlEg:n:p:v:a:x:c:j:m:G:M:D:A:S:P:L:Q:' option; do
      case "$option" in
        h) echo "$usage"
           exit
           ;;
        p) DB_ADDRESS=$OPTARG
           ;;
        m) AM_ADDRESS="-m $OPTARG"
           ALERT_MANAGER_ADDRESS=$OPTARG
           ;;
        L) LOKI_ADDRESS=$OPTARG
           ;;
        :) printf "missing argument for -%s\n" "$OPTARG" >&2
           echo "$usage" >&2
           exit 1
           ;;
       \?) printf "illegal option: -%s\n" "$OPTARG" >&2
           echo "$usage" >&2
           exit 1
           ;;
      esac
    done
fi
mkdir -p grafana/provisioning/datasources
rm -f grafana/provisioning/datasources/datasource.yaml
sed "s/DB_ADDRESS/$DB_ADDRESS/" grafana/datasource.yml | sed "s/AM_ADDRESS/$ALERT_MANAGER_ADDRESS/" > grafana/provisioning/datasources/datasource.yaml
if [ -z "$LOKI_ADDRESS" ]; then
    rm -f grafana/provisioning/datasources/datasource.loki.yaml
else
    sed "s/LOKI_ADDRESS/$LOKI_ADDRESS/" grafana/datasource.loki.yml> grafana/provisioning/datasources/datasource.loki.yaml
fi
if [ -z "$SCYLLA_USER" ] || [ -z "$SCYLLA_PSSWD" ]; then
    cp grafana/datasource.scylla.yml grafana/provisioning/datasources/datasource.scylla.yml
else
    sed "s/SCYLLA_USER/$SCYLLA_USER/" grafana/datasource.psswd.scylla.yml |sed "s/SCYLLA_PSSWD/$SCYLLA_PSSWD/">grafana/provisioning/datasources/datasource.scylla.yml
fi
