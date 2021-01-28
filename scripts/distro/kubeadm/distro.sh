
function kubeadm_discover_private_ip() {
    local private_address

    private_address="$(cat /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null | grep advertise-address | awk -F'=' '{ print $2 }')"

    # This is needed on k8s 1.18.x as $PRIVATE_ADDRESS is found to have a newline
    echo "${private_address}" | tr -d '\n'
}

function kubeadm_get_kubeconfig() {
    echo "/etc/kubernetes/admin.conf"
}

function kubeadm_get_containerd_sock() {
    echo "/run/containerd/containerd.sock"
}

function kubeadm_get_client_kube_apiserver_crt() {
    echo "/etc/kubernetes/pki/apiserver-kubelet-client.crt"
}

function kubeadm_get_client_kube_apiserver_key() {
    echo "/etc/kubernetes/pki/apiserver-kubelet-client.key"
}

function kubeadm_get_server_ca() {
    echo "/etc/kubernetes/pki/ca.crt"
}

function kubeadm_addon_for_each() {
    local cmd="$1"

    $cmd aws "$AWS_VERSION"
    $cmd nodeless "$NODELESS_VERSION"
    $cmd calico "$CALICO_VERSION" "$CALICO_S3_OVERRIDE"
    $cmd weave "$WEAVE_VERSION" "$WEAVE_S3_OVERRIDE"
    $cmd rook "$ROOK_VERSION" "$ROOK_S3_OVERRIDE"
    $cmd openebs "$OPENEBS_VERSION" "$OPENEBS_S3_OVERRIDE"
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
    $cmd metrics-server "$METRICS_SERVER_VERSION" "$METRICS_SERVER_S3_OVERRIDE"
}