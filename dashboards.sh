if [[ -z "$DASHBOARDS" ]]; then
    DASHBOARDS=(scylla-overview scylla-detailed scylla-io scylla-cpu scylla-os scylla-cql scylla-errors alternator)
else
    read -ra DASHBOARDS <<< "$DASHBOARDS"
fi
