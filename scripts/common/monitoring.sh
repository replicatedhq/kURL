
function maybe_apply_prometheus_monitor() {
    if [ -n "$PROMETHEUS_VERSION" ]; then
        if [ -n "$ROOK_VERSION" ]; then
            echo "Applying Prometheus service monitor custom resource"
            curl "https://raw.githubusercontent.com/rook/rook/v${ROOK_VERSION}/deploy/examples/monitoring/service-monitor.yaml" \
                | sed --expression='s/namespace: rook-ceph/namespace: monitoring/g' | kubectl -n monitoring apply -f -
        fi
    fi
}
