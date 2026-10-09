#!/bin/bash

set -e

# shellcheck disable=SC1091
. ./scripts/common/common.sh
# shellcheck disable=SC1091
. ./addons/calico/3.9.1/install.sh

function calico_existing_pod_cidr() {
    # shellcheck disable=SC2317
    return 0
}

function setUp() {
    TEST_DIR="$(mktemp -d)"
    DIR="$TEST_DIR"
    mkdir -p "$DIR/addons/calico/3.9.1" "$DIR/kustomize/kubeadm/init-patches"
    cp ./addons/calico/3.9.1/kubeadm-cluster-config-v1beta2.yml "$DIR/addons/calico/3.9.1/"
    cp ./addons/calico/3.9.1/kubeadm-cluster-config-v1beta4.yml "$DIR/addons/calico/3.9.1/"
    cp ./addons/calico/3.9.1/kubeproxy-config-v1alpha1.yml "$DIR/addons/calico/3.9.1/"
}

function tearDown() {
    rm -rf "$TEST_DIR"
}

function test_calico_pre_init_uses_v1beta2_patch_shape_by_default() {
    kubeadm_conf_api_version() { echo "v1beta3"; }

    calico_pre_init

    assertEquals "1" "$(grep -c 'apiVersion: kubeadm.k8s.io/v1beta2' "$DIR/kustomize/kubeadm/init-patches/calico-kubeadm-cluster-config-v1beta2.yml" || true)"
}

function test_calico_pre_init_uses_v1beta4_patch_shape_for_kubernetes_137() {
    kubeadm_conf_api_version() { echo "v1beta4"; }

    calico_pre_init

    assertEquals "1" "$(grep -c 'apiVersion: kubeadm.k8s.io/v1beta4' "$DIR/kustomize/kubeadm/init-patches/calico-kubeadm-cluster-config-v1beta2.yml" || true)"
    assertEquals "1" "$(grep -c 'name: allocate-node-cidrs' "$DIR/kustomize/kubeadm/init-patches/calico-kubeadm-cluster-config-v1beta2.yml" || true)"
}

# shellcheck disable=SC1091
. shunit2
