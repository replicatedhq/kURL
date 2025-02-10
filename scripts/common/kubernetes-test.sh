#!/bin/bash

set -e

. ./scripts/common/common.sh
. ./scripts/common/kubernetes.sh

function test_kubernetes_version_minor() {
    assertEquals "v1.20.0" "20" "$(kubernetes_version_minor "v1.20.0")"
    assertEquals "v1.20.0" "20" "$(kubernetes_version_minor "1.20.0")"
}

function test_kubernetes_configure_pause_image_upgrade() {
    systemctl() {
        #shellcheck disable=SC2317
        true # noop
    }
    kubernetes_containerd_pause_image() {
        #shellcheck disable=SC2317
        echo "registry.k8s.io/pause:3.6"
    }

    KUBELET_FLAGS_FILE=$(mktemp)
    echo 'KUBELET_KUBEADM_ARGS="--container-runtime=remote --container-runtime-endpoint=unix:///run/containerd/containerd.sock --node-ip=10.128.0.79 --node-labels=kurl.sh/cluster=true, --pod-infra-container-image=k8s.gcr.io/pause:3.5"' > "$KUBELET_FLAGS_FILE"

    kubernetes_configure_pause_image_upgrade

    local expected='KUBELET_KUBEADM_ARGS="--container-runtime=remote --container-runtime-endpoint=unix:///run/containerd/containerd.sock --node-ip=10.128.0.79 --node-labels=kurl.sh/cluster=true, --pod-infra-container-image=registry.k8s.io/pause:3.6"'
    assertEquals "should replace correctly with flag at end" "$expected" "$(cat "$KUBELET_FLAGS_FILE")"

    echo 'KUBELET_KUBEADM_ARGS="--container-runtime=remote --container-runtime-endpoint=unix:///run/containerd/containerd.sock --node-ip=10.128.0.79 --pod-infra-container-image=k8s.gcr.io/pause:3.5 --node-labels=kurl.sh/cluster=true,"' > "$KUBELET_FLAGS_FILE"

    kubernetes_configure_pause_image_upgrade

    local expected='KUBELET_KUBEADM_ARGS="--container-runtime=remote --container-runtime-endpoint=unix:///run/containerd/containerd.sock --node-ip=10.128.0.79 --pod-infra-container-image=registry.k8s.io/pause:3.6 --node-labels=kurl.sh/cluster=true,"'
    assertEquals "should replace correctly with flag in middle" "$expected" "$(cat "$KUBELET_FLAGS_FILE")"

    rm "$KUBELET_FLAGS_FILE"
}

. shunit2
