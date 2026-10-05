#!/bin/bash

set -e

. ./scripts/common/common.sh
. ./scripts/common/kubernetes.sh

function test_kubernetes_node_has_image() {
    function kubernetes_node_images() {
        echo "docker.io/org/image-1:1.0
org/image-2:1.0
image-3:1.0
library/image-4:1.0
quay.io/org/image-5:1.0
quay.io/org/image-6"
    }
    export kubernetes_node_images

    assertEquals "docker.io/org/image-1:1.0 org/image-1:1.0" "0" "$(kubernetes_node_has_image "node-1" "org/image-1:1.0"; echo $?)"
    assertEquals "docker.io/org/image-1:1.0 docker.io/org/image-1:1.0" "0" "$(kubernetes_node_has_image "node-1" "docker.io/org/image-1:1.0"; echo $?)"

    assertEquals "org/image-2:1.0 org/image-2:1.0" "0" "$(kubernetes_node_has_image "node-1" "org/image-2:1.0"; echo $?)"
    assertEquals "org/image-2:1.0 docker.io/org/image-2:1.0" "0" "$(kubernetes_node_has_image "node-1" "docker.io/org/image-2:1.0"; echo $?)"

    assertEquals "image-3:1.0 image-3:1.0" "0" "$(kubernetes_node_has_image "node-1" "image-3:1.0"; echo $?)"
    assertEquals "image-3:1.0 library/image-3:1.0" "0" "$(kubernetes_node_has_image "node-1" "library/image-3:1.0"; echo $?)"
    assertEquals "image-3:1.0 docker.io/library/image-3:1.0" "0" "$(kubernetes_node_has_image "node-1" "docker.io/library/image-3:1.0"; echo $?)"

    assertEquals "library/image-4:1.0 image-4:1.0" "0" "$(kubernetes_node_has_image "node-1" "image-4:1.0"; echo $?)"
    assertEquals "library/image-4:1.0 library/image-4:1.0" "0" "$(kubernetes_node_has_image "node-1" "library/image-4:1.0"; echo $?)"
    assertEquals "library/image-4:1.0 docker.io/library/image-4:1.0" "0" "$(kubernetes_node_has_image "node-1" "docker.io/library/image-4:1.0"; echo $?)"

    assertEquals "quay.io/org/image-5:1.0 quay.io/org/image-5:1.0" "0" "$(kubernetes_node_has_image "node-1" "quay.io/org/image-5:1.0"; echo $?)"

    assertEquals "quay.io/org/image-6 quay.io/org/image-6" "0" "$(kubernetes_node_has_image "node-1" "quay.io/org/image-6"; echo $?)"
    assertEquals "quay.io/org/image-6 quay.io/org/image-6:latest" "0" "$(kubernetes_node_has_image "node-1" "quay.io/org/image-6:latest"; echo $?)"

    assertEquals "org/image-n:1.0" "1" "$(kubernetes_node_has_image "node-1" "org/image-n:1.0"; echo $?)"
    assertEquals "image-n:1.0" "1" "$(kubernetes_node_has_image "node-1" "image-n:1.0"; echo $?)"
    assertEquals "docker.io/org/image-n:1.0" "1" "$(kubernetes_node_has_image "node-1" "docker.io/org/image-n:1.0"; echo $?)"
    assertEquals "quay.io/org/image-n:1.0" "1" "$(kubernetes_node_has_image "node-1" "quay.io/org/image-n:1.0"; echo $?)"
    assertEquals "quay.io/org/image-n" "1" "$(kubernetes_node_has_image "node-1" "quay.io/org/image-n"; echo $?)"
    assertEquals "quay.io/org/image-5:2.0" "1" "$(kubernetes_node_has_image "node-1" "quay.io/org/image-5:2.0"; echo $?)"
}

function test_kubernetes_configure_kubeadm_images_etcd_override_first_init_only() {
    function kubeadm_customize_config() {
        #shellcheck disable=SC2317
        true # noop
    }
    function insert_patches_strategic_merge() {
        #shellcheck disable=SC2317
        true # noop
    }

    local tmpdir=
    tmpdir=$(mktemp -d)
    DIR="$tmpdir"
    KUBERNETES_VERSION="1.36.5"
    KUBEADM_CONF_DIR="$tmpdir/kubeadm-conf"
    mkdir -p "$tmpdir/packages/kubernetes/$KUBERNETES_VERSION"
    cat > "$tmpdir/packages/kubernetes/$KUBERNETES_VERSION/kubeadm-image-overrides" <<EOF
etcd proxy.replicated.com/anonymous/registry.k8s.io/etcd:v3.6.15 registry.k8s.io/etcd:3.6.8-0
EOF

    local kustomize_dir="$tmpdir/kustomize"
    mkdir -p "$kustomize_dir"
    touch "$kustomize_dir/kustomization.yaml"

    # Given a fresh node with no existing etcd static pod manifest, the first kubeadm init
    # should still apply the securebuild etcd image/version override.
    ETCD_STATIC_MANIFEST="$tmpdir/manifests/etcd.yaml"

    kubernetes_configure_kubeadm_images "$kustomize_dir" InitConfiguration

    assertEquals "etcd override should be written on first init" "0" "$([ -f "$kustomize_dir/kurl-etcd-image.yaml" ]; echo $?)"
    assertEquals "etcd image should be the securebuild etcd" "0" "$(grep -q 'proxy.replicated.com/anonymous/registry.k8s.io' "$kustomize_dir/kurl-etcd-image.yaml"; echo $?)"

    # Given a node whose control plane was already initialized (an etcd static pod manifest
    # already exists), a re-run of kubeadm init (e.g. a later storage-migration step) must NOT
    # write a new etcd image/version override — the running etcd must be left alone.
    rm -rf "$kustomize_dir"
    mkdir -p "$kustomize_dir"
    touch "$kustomize_dir/kustomization.yaml"
    mkdir -p "$(dirname "$ETCD_STATIC_MANIFEST")"
    touch "$ETCD_STATIC_MANIFEST"

    kubernetes_configure_kubeadm_images "$kustomize_dir" InitConfiguration

    assertEquals "etcd override should NOT be written on a re-init" "1" "$([ -f "$kustomize_dir/kurl-etcd-image.yaml" ]; echo $?)"

    unset ETCD_STATIC_MANIFEST
    rm -rf "$tmpdir"
}

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
