#!/bin/bash

set -e

# shellcheck disable=SC1091
. ./scripts/common/common.sh
# shellcheck disable=SC1091
. ./scripts/distro/kubeadm/distro.sh

function test_kubeadm_conf_api_version_v1beta2() {
    local KUBERNETES_TARGET_VERSION_MINOR=25
    assertEquals "v1beta2" "$(kubeadm_conf_api_version)"
}

function test_kubeadm_conf_api_version_v1beta3() {
    local KUBERNETES_TARGET_VERSION_MINOR=26
    assertEquals "v1beta3" "$(kubeadm_conf_api_version)"

    KUBERNETES_TARGET_VERSION_MINOR=36
    assertEquals "v1beta3" "$(kubeadm_conf_api_version)"
}

function test_kubeadm_conf_api_version_v1beta4() {
    local KUBERNETES_TARGET_VERSION_MINOR=37
    assertEquals "v1beta4" "$(kubeadm_conf_api_version)"

    KUBERNETES_TARGET_VERSION_MINOR=38
    assertEquals "v1beta4" "$(kubeadm_conf_api_version)"
}

# shellcheck disable=SC1091
. shunit2
