# TODO (dan): consolidate this with the rke2 distro
function k3s_discover_private_ip() {
    echo "$(cat /var/lib/rancher/k3s/agent/pod-manifests/etcd.yaml 2>/dev/null | grep initial-cluster | grep -o "${HOSTNAME}-[a-z0-9]*=https*://[^\",]*" | sed -n -e 's/.*https*:\/\/\(.*\):.*/\1/p')"
}

function k3s_get_kubeconfig() {
    echo "/etc/rancher/k3s/k3s.yaml"
}

function k3s_get_containerd_sock() {
    echo "/run/k3s/containerd/containerd.sock"
}

function k3s_get_client_kube_apiserver_crt() {
    echo "/var/lib/rancher/k3s/server/tls/client-kube-apiserver.crt"
}

function k3s_get_client_kube_apiserver_key() {
    echo "/var/lib/rancher/k3s/server/tls/client-kube-apiserver.key"
}

function k3s_get_server_ca() {
    echo "/var/lib/rancher/k3s/server/tls/server-ca.crt"
}

function k3s_get_server_ca_key() {
    echo "/var/lib/rancher/k3s/server/tls/server-ca.key"
}

function k3s_addon_for_each() {
    local cmd="$1"

    if [ -n "$METRICS_SERVER_VERSION" ] && [ -z "$METRICS_SERVER_IGNORE" ]; then
        logWarn "⚠️  Metrics Server is distributed as part of K3S; the version specified in the installer will be ignored."
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
}

function k3s_reset() {
    . /usr/local/bin/k3s-uninstall.sh
}

function k3s_containerd_restart() {
    k3s_restart
}

function k3s_registry_containerd_configure() {
    local registry_ip="$1"

    if grep -qs ' "${registry_ip}":' /etc/rancher/k3s/registries.yaml; then
        echo "Registry ${registry_ip} TLS already configured for containerd"
        return 0
    fi

    mkdir -p /etc/rancher/k3s/

    if [ ! -f /etc/rancher/k3s/registries.yaml ] || ! grep -qs '^configs:' /etc/rancher/k3s/registries.yaml ; then
        echo "configs:" >> /etc/rancher/k3s/registries.yaml
    fi

    cat >> /etc/rancher/k3s/registries.yaml <<EOF
  "${registry_ip}":
    tls:
      ca_file: "$(k3s_get_server_ca)"
EOF

    CONTAINERD_NEEDS_RESTART=1
}

function k3s_api_is_healthy() {
    kubectl get --raw="/readyz" &> /dev/null
}
