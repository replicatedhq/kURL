#!/bin/bash

set -e

# shellcheck disable=SC1091
. ./scripts/common/common.sh
# shellcheck disable=SC1091
. ./scripts/common/containerd.sh
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

function test_containerd_pre_init_bails_on_sub_2x_containerd_with_kubernetes_137() {
    kubeadm_conf_api_version() { echo "v1beta4"; }
    CONTAINERD_VERSION="1.7.29"
    mkdir -p "$DIR/addons/containerd/$CONTAINERD_VERSION"

    local result exit_code=0
    result="$( (containerd_pre_init) 2>&1 || true)"
    echo "$result" | grep -q "containerd 2.x"
    assertEquals "bails mentioning containerd 2.x requirement" "0" "$?"

    (containerd_pre_init) >/dev/null 2>&1 || exit_code=$?
    assertEquals "exits non-zero" "1" "$exit_code"
}

function test_containerd_join_bails_on_sub_2x_containerd_with_kubernetes_137() {
    kubeadm_conf_api_version() { echo "v1beta4"; }
    CONTAINERD_VERSION="1.7.29"
    mkdir -p "$DIR/addons/containerd/$CONTAINERD_VERSION"

    local exit_code=0
    (containerd_join) >/dev/null 2>&1 || exit_code=$?
    assertEquals "exits non-zero" "1" "$exit_code"
}

function test_containerd_pre_init_allows_2x_containerd_with_kubernetes_137() {
    kubeadm_conf_api_version() { echo "v1beta4"; }
    CONTAINERD_VERSION="2.3.6"
    mkdir -p "$DIR/addons/containerd/$CONTAINERD_VERSION"
    echo "kubeletExtraArgs-list-init" > "$DIR/addons/containerd/$CONTAINERD_VERSION/kubeadm-init-config-v1beta4.yaml"

    local exit_code=0
    (containerd_pre_init) >/dev/null 2>&1 || exit_code=$?
    assertEquals "does not bail" "0" "$exit_code"
}

# shellcheck disable=SC1091
. shunit2
