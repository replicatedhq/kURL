#!/bin/bash

set -e

# shellcheck disable=SC1091
. ./scripts/common/common.sh
# shellcheck disable=SC1091
. ./addons/nodeless/0.0.1/install.sh

function replace_cri() {
    # shellcheck disable=SC2317
    return 0
}

function setUp() {
    TEST_DIR="$(mktemp -d)"
    DIR="$TEST_DIR"
    mkdir -p "$DIR/addons/nodeless/0.0.1" "$DIR/kustomize/kubeadm/init-patches" "$DIR/kustomize/kubeadm/join-patches"
    cp ./addons/nodeless/0.0.1/kubeadm-init-config-v1beta2.yml "$DIR/addons/nodeless/0.0.1/"
    cp ./addons/nodeless/0.0.1/kubeadm-init-config-v1beta4.yml "$DIR/addons/nodeless/0.0.1/"
    cp ./addons/nodeless/0.0.1/kubeadm-join-config-v1beta2.yaml "$DIR/addons/nodeless/0.0.1/"
    cp ./addons/nodeless/0.0.1/kubeadm-join-config-v1beta4.yaml "$DIR/addons/nodeless/0.0.1/"
    cp ./addons/nodeless/0.0.1/kubeproxy-config-v1alpha1.yml "$DIR/addons/nodeless/0.0.1/"
}

function tearDown() {
    rm -rf "$TEST_DIR"
}

function test_nodeless_pre_init_uses_v1beta2_patch_shape_by_default() {
    kubeadm_conf_api_version() { echo "v1beta3"; }

    nodeless_pre_init

    assertEquals "1" "$(grep -c 'apiVersion: kubeadm.k8s.io/v1beta2' "$DIR/kustomize/kubeadm/init-patches/nodeless-kubeadm-init-config-v1beta2.yml" || true)"
}

function test_nodeless_pre_init_uses_v1beta4_patch_shape_for_kubernetes_137() {
    kubeadm_conf_api_version() { echo "v1beta4"; }

    nodeless_pre_init

    assertEquals "1" "$(grep -c 'apiVersion: kubeadm.k8s.io/v1beta4' "$DIR/kustomize/kubeadm/init-patches/nodeless-kubeadm-init-config-v1beta2.yml" || true)"
    assertEquals "2" "$(grep -c '  value:' "$DIR/kustomize/kubeadm/init-patches/nodeless-kubeadm-init-config-v1beta2.yml" || true)"
}

function test_nodeless_join_uses_v1beta2_patch_shape_by_default() {
    kubeadm_conf_api_version() { echo "v1beta3"; }

    nodeless_join

    assertEquals "1" "$(grep -c 'apiVersion: kubeadm.k8s.io/v1beta2' "$DIR/kustomize/kubeadm/join-patches/nodeless-kubeadm-join-config-v1beta2.yaml" || true)"
}

function test_nodeless_join_uses_v1beta4_patch_shape_for_kubernetes_137() {
    kubeadm_conf_api_version() { echo "v1beta4"; }

    nodeless_join

    assertEquals "1" "$(grep -c 'apiVersion: kubeadm.k8s.io/v1beta4' "$DIR/kustomize/kubeadm/join-patches/nodeless-kubeadm-join-config-v1beta2.yaml" || true)"
}

# shellcheck disable=SC1091
. shunit2
