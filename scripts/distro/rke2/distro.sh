# TODO (dan): consolidate this with the k3s distro

function rke2_discover_private_ip() {
    echo "$(cat /var/lib/rancher/rke2/agent/pod-manifests/etcd.yaml 2>/dev/null | grep initial-cluster | grep -o "${HOSTNAME}-[a-z0-9]*=https*://[^\",]*" | sed -n -e 's/.*https*:\/\/\(.*\):.*/\1/p')"
}

function rke2_get_kubeconfig() {
    echo "/etc/rancher/rke2/rke2.yaml"
}

function rke2_get_containerd_sock() {
    echo "/run/k3s/containerd/containerd.sock"
}

function rke2_get_client_kube_apiserver_crt() {
    echo "/var/lib/rancher/rke2/server/tls/client-kube-apiserver.crt"
}

function rke2_get_client_kube_apiserver_key() {
    echo "/var/lib/rancher/rke2/server/tls/client-kube-apiserver.key"
}

function rke2_get_server_ca() {
    echo "/var/lib/rancher/rke2/server/tls/server-ca.crt"
}

function rke2_get_server_ca_key() {
    echo "/var/lib/rancher/rke2/server/tls/server-ca.key"
}

function rke2_addon_for_each() {
    local cmd="$1"

    if [ -n "$METRICS_SERVER_VERSION" ] && [ -z "$METRICS_SERVER_IGNORE" ]; then
        logWarn "⚠️  Metrics Server is distributed as part of RKE2; the version specified in the installer will be ignored."
        METRICS_SERVER_IGNORE=true
    fi

    $cmd aws "$AWS_VERSION"
    $cmd nodeless "$NODELESS_VERSION"
    $cmd calico "$CALICO_VERSION" "$CALICO_S3_OVERRIDE"
    $cmd weave "$WEAVE_VERSION" "$WEAVE_S3_OVERRIDE"
    $cmd rook "$ROOK_VERSION" "$ROOK_S3_OVERRIDE"
    $cmd openebs "$OPENEBS_VERSION" "$OPENEBS_S3_OVERRIDE"
    $cmd longhorn "$LONGHORN_VERSION" "$LONGHORN_S3_OVERRIDE"
    $cmd minio "$MINIO_VERSION" "$MINIO_S3_OVERRIDE"
    $cmd contour "$CONTOUR_VERSION" "$CONTOUR_S3_OVERRIDE"
    $cmd registry "$REGISTRY_VERSION" "$REGISTRY_S3_OVERRIDE"
    $cmd prometheus "$PROMETHEUS_VERSION" "$PROMETHEUS_S3_OVERRIDE"
    $cmd kotsadm "$KOTSADM_VERSION" "$KOTSADM_S3_OVERRIDE"
    $cmd velero "$VELERO_VERSION" "$VELERO_S3_OVERRIDE"
    $cmd fluentd "$FLUENTD_VERSION" "$FLUENTD_S3_OVERRIDE"
    $cmd ekco "$EKCO_VERSION" "$EKCO_S3_OVERRIDE"
    $cmd collectd "$COLLECTD_VERSION" "$COLLECTD_S3_OVERRIDE"
    $cmd cert-manager "$CERT_MANAGER_VERSION" "$CERT_MANAGER_S3_OVERRIDE"
    $cmd sonobuoy "$SONOBUOY_VERSION" "$SONOBUOY_S3_OVERRIDE"
    $cmd goldpinger "$GOLDPINGER_VERSION" "$GOLDPINGER_S3_OVERRIDE"
}

function rke2_reset() {
    . /usr/bin/rke2-uninstall.sh
}

function rke2_containerd_restart() {
    rke2_restart
}

function rke2_registry_containerd_configure() {
    local registry_ip="$1"

    if grep -qs ' "${registry_ip}":' /etc/rancher/rke2/registries.yaml; then
        echo "Registry ${registry_ip} TLS already configured for containerd"
        return 0
    fi

    mkdir -p /etc/rancher/rke2/

    if [ ! -f /etc/rancher/rke2/registries.yaml ] || ! grep -qs '^configs:' /etc/rancher/rke2/registries.yaml ; then
        echo "configs:" >> /etc/rancher/rke2/registries.yaml
    fi

    cat >> /etc/rancher/rke2/registries.yaml <<EOF
  "${registry_ip}":
    tls:
      ca_file: "$(rke2_get_server_ca)"
EOF

    CONTAINERD_NEEDS_RESTART=1
}

function rke2_api_is_healthy() {
    kubectl get --raw="/readyz" &> /dev/null
}
