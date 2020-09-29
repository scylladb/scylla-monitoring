if [[ -z "$DASHBOARDS" ]]; then
    DASHBOARDS=(scylla-overview scylla-detailed scylla-os scylla-cql scylla-advanced alternator)
else
    read -ra DASHBOARDS <<< "$DASHBOARDS"
fi
