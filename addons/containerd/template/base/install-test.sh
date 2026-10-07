#!/bin/bash

set -e

# shellcheck disable=SC1091
. ./scripts/common/common.sh
# shellcheck disable=SC1091
. ./addons/containerd/template/base/install.sh

function containerd_host_init() {
    # shellcheck disable=SC2317
    return 0
}

function setUp() {
    TEST_DIR="$(mktemp -d)"
    # shellcheck disable=SC2034
    DIR="$TEST_DIR"
    CONTAINERD_VERSION="9.9.9"
    mkdir -p "$DIR/addons/containerd/$CONTAINERD_VERSION"
    mkdir -p "$DIR/kustomize/kubeadm/init-patches"
    mkdir -p "$DIR/kustomize/kubeadm/join-patches"

    echo "kubeletExtraArgs-map-init" > "$DIR/addons/containerd/$CONTAINERD_VERSION/kubeadm-init-config-v1beta2.yaml"
    echo "kubeletExtraArgs-list-init" > "$DIR/addons/containerd/$CONTAINERD_VERSION/kubeadm-init-config-v1beta4.yaml"
    echo "kubeletExtraArgs-map-join" > "$DIR/addons/containerd/$CONTAINERD_VERSION/kubeadm-join-config-v1beta2.yaml"
    echo "kubeletExtraArgs-list-join" > "$DIR/addons/containerd/$CONTAINERD_VERSION/kubeadm-join-config-v1beta4.yaml"
}

function tearDown() {
    rm -rf "$TEST_DIR"
}

function test_containerd_pre_init_uses_v1beta2_patch_shape_by_default() {
    kubeadm_conf_api_version() { echo "v1beta3"; }

    containerd_pre_init

    assertEquals "kubeletExtraArgs-map-init" "$(cat "$DIR/kustomize/kubeadm/init-patches/containerd-kubeadm-init-config-v1beta2.yml")"
}

function test_containerd_pre_init_uses_v1beta4_patch_shape_for_kubernetes_137() {
    kubeadm_conf_api_version() { echo "v1beta4"; }

    containerd_pre_init

    assertEquals "kubeletExtraArgs-list-init" "$(cat "$DIR/kustomize/kubeadm/init-patches/containerd-kubeadm-init-config-v1beta2.yml")"
}

function test_containerd_join_uses_v1beta2_patch_shape_by_default() {
    kubeadm_conf_api_version() { echo "v1beta3"; }

    containerd_join

    assertEquals "kubeletExtraArgs-map-join" "$(cat "$DIR/kustomize/kubeadm/join-patches/containerd-kubeadm-join-config-v1beta2.yml")"
}

function test_containerd_join_uses_v1beta4_patch_shape_for_kubernetes_137() {
    kubeadm_conf_api_version() { echo "v1beta4"; }

    containerd_join

    assertEquals "kubeletExtraArgs-list-join" "$(cat "$DIR/kustomize/kubeadm/join-patches/containerd-kubeadm-join-config-v1beta2.yml")"
}

# shellcheck disable=SC1091
. shunit2
