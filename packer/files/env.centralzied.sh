RUN_THANOS=1
DOCKER_PARAMS["thanos"]="--grpc-client-tls-skip-verify --grpc-client-tls-ca=/security/monitorCA.crt --grpc-client-tls-cert=/security/monitor.crt --grpc-client-tls-key=/security/monitor.key  --grpc-client-tls-secure --store.sd-files=/store/thanos_stores.yml"
DOCKER_LIMITS["thanos"]="-v /home/centos/scylla-grafana-monitoring-scylla-monitoring/security:/security:z -v /home/centos/scylla-grafana-monitoring-scylla-monitoring/prometheus:/store:z"
HOME_DASHBOARD="/var/lib/grafana/dashboards/ver_master/scylla-centralized-kiosk.master.json"
DASHBOARDS=(scylla-centralized scylla-centralized-kiosk scylla-centralized-graph-kiosk)
VERSIONS="master"
DATA_DIR="/var/lib/promehteus-data/"
RUN_LOKI=0
