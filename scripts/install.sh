#!/bin/bash

set -e

DIR=.
YAML_DIR=../yaml
KUBEADM_CONF_DIR=/opt/replicated
KUBEADM_CONF_FILE="$KUBEADM_CONF_DIR/kubeadm.conf"

. "$DIR/common/common.sh"
. "$DIR/common/contour.sh"
. "$DIR/common/discover.sh"
. "$DIR/common/flags.sh"
. "$DIR/common/preflights.sh"
. "$DIR/common/prepare.sh"
. "$DIR/common/prompts.sh"
. "$DIR/common/yaml.sh"

function init() {
    logStep "Initialize Kubernetes"

    maybeGenerateBootstrapToken

    if [ "$LOAD_BALANCER_ADDRESS_CHANGED" = "1" ]; then
        handleLoadBalancerAddressChangedPreInit
    fi

	mkdir -p "$KUBEADM_CONF_DIR"
	render_yaml kubeadm-init-config-v1beta2.yml > "$KUBEADM_CONF_FILE"
	render_yaml kubeadm-cluster-config-v1beta2.yml >> "$KUBEADM_CONF_FILE"
    render_yaml kubeproxy-config-v1alpha1.yml >> "$KUBEADM_CONF_FILE"

    kubeadm init \
        --ignore-preflight-errors=all \
        --config /opt/replicated/kubeadm.conf \
        | tee /tmp/kubeadm-init

    exportKubeconfig

    waitForNodes

    DID_INIT_KUBERNETES=1
    logSuccess "Kubernetes Master Initialized"

    if [ "$LOAD_BALANCER_ADDRESS_CHANGED" = "1" ]; then
        handleLoadBalancerAddressChangedPostInit
    fi

    kubectl cluster-info
    logSuccess "Cluster Initialized"
}

maybeGenerateBootstrapToken() {
    if [ -z "$BOOTSTRAP_TOKEN" ]; then
        logStep "generate kubernetes bootstrap token"
        BOOTSTRAP_TOKEN=$(kubeadm token generate)
    fi
    echo "Kubernetes bootstrap token: ${BOOTSTRAP_TOKEN}"
    echo "This token will expire in 24 hours"
}

function main() {
    export KUBECONFIG=/etc/kubernetes/admin.conf
    requireRootUser
    discover
    flags
    preflights
    prompts
    prepare
    init
    weave
    rook
    contour
}

main "$@"
