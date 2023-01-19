#!/bin/bash

function k0s_addon_for_each() {
    local cmd="$1"

    $cmd rook "$ROOK_VERSION" "$ROOK_S3_OVERRIDE"
    $cmd ekco "$EKCO_VERSION" "$EKCO_S3_OVERRIDE"
    $cmd openebs "$OPENEBS_VERSION" "$OPENEBS_S3_OVERRIDE"
    $cmd minio "$MINIO_VERSION" "$MINIO_S3_OVERRIDE"
    $cmd contour "$CONTOUR_VERSION" "$CONTOUR_S3_OVERRIDE"
    $cmd registry "$REGISTRY_VERSION" "$REGISTRY_S3_OVERRIDE"
    $cmd prometheus "$PROMETHEUS_VERSION" "$PROMETHEUS_S3_OVERRIDE"
    $cmd kotsadm "$KOTSADM_VERSION" "$KOTSADM_S3_OVERRIDE"
    $cmd velero "$VELERO_VERSION" "$VELERO_S3_OVERRIDE"
}

function k0s_discover_private_ip() {
    k0s config create 2>/dev/null | grep peerAddress | awk '{ print $2 }'
}

function k0s_registry_containerd_configure() {
    local registry_ip="$1"

    export CONTAINERD_NEEDS_RESTART

    mkdir -p /etc/k0s/
    if [ ! -f /etc/k0s/containerd.toml ]; then
        /var/lib/k0s/bin/containerd config default > /etc/k0s/containerd.toml
        CONTAINERD_NEEDS_RESTART=1
    fi

    # TODO: this is brittle, use kurl_util toml tool
    if ! grep -Fq 'root = "/var/lib/k0s/containerd"' /etc/k0s/containerd.toml ; then
        sed -i 's|^root = .*|root = "/var/lib/k0s/containerd"|' /etc/k0s/containerd.toml
        CONTAINERD_NEEDS_RESTART=1
    fi
    if ! grep -Fq 'state = "/run/k0s/containerd"' /etc/k0s/containerd.toml ; then
        sed -i 's|^state = .*|state = "/run/k0s/containerd"|' /etc/k0s/containerd.toml
        CONTAINERD_NEEDS_RESTART=1
    fi
    if ! grep -Fq 'address = "/run/k0s/containerd.sock"' /etc/k0s/containerd.toml ; then
        sed -i 's|^  address = "/run/containerd/containerd.sock"|  address = "/run/k0s/containerd.sock"|' /etc/k0s/containerd.toml
        CONTAINERD_NEEDS_RESTART=1
    fi

    if ! grep -Fq "plugins.\"io.containerd.grpc.v1.cri\".registry.configs.\"${registry_ip}\".tls" /etc/k0s/containerd.toml ; then
        cat >> /etc/k0s/containerd.toml <<EOF
[plugins."io.containerd.grpc.v1.cri".registry.configs."${registry_ip}".tls]
  ca_file = "/etc/kubernetes/pki/ca.crt"
EOF
        CONTAINERD_NEEDS_RESTART=1
    fi
}

function k0s_get_client_kube_apiserver_crt() {
    echo "/var/lib/k0s/pki/apiserver-kubelet-client.crt"
}

function k0s_get_client_kube_apiserver_key() {
    echo "/var/lib/k0s/pki/apiserver-kubelet-client.key"
}

function k0s_get_server_ca() {
    echo "/var/lib/k0s/pki/ca.crt"
}

function k0s_get_server_ca_key() {
    echo "/var/lib/k0s/pki/ca.key"
}

function k0s_api_is_healthy() {
    k0s status 2>/dev/null | grep -q 'Kube-api probing successful: true' 2>&1
}

function k0s_get_kubeconfig() {
    echo "/var/lib/k0s/pki/admin.conf"
}

function k0s_token_create_worker() {
    k0s token create --role=worker --expiry=100h
}

function k0s_token_create_controller() {
    k0s token create --role=controller --expiry=1h
}

function k0s_get_containerd_sock() {
    echo "FAKE"
}

function k0s_preflights() {
    require64Bit
    bailIfUnsupportedOS
    mustSwapoff
    prompt_if_docker_unsupported_os
    check_docker_k8s_version
    kotsadm_prerelease
    host_nameservers_reachable
    return 0
}

function k0s_join_flags_worker() {
    local token=
    token="$(k0s_token_create_worker)"
    echo " experimental-k0s kubernetes-version=${K0S_VERSION} join-token=${token}"
}

function k0s_join_flags_control_plane() {
    local token=
    token="$(k0s_token_create_controller)"
    echo " experimental-k0s control-plane kubernetes-version=${K0S_VERSION} join-token=${token}"
}

function k0s_setup_outro() {
    # do nothing
    return
}
