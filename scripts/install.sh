#!/bin/bash

set -e

DIR=..
YAML_DIR="$DIR/yaml"
KUBEADM_CONF_DIR=/opt/replicated
KUBEADM_CONF_FILE="$KUBEADM_CONF_DIR/kubeadm.conf"

. "$DIR/Manifest"
. "$DIR/scripts/common/common.sh"
. "$DIR/scripts/common/contour.sh"
. "$DIR/scripts/common/discover.sh"
. "$DIR/scripts/common/flags.sh"
. "$DIR/scripts/common/preflights.sh"
. "$DIR/scripts/common/prepare.sh"
. "$DIR/scripts/common/prompts.sh"
. "$DIR/scripts/common/rook.sh"
. "$DIR/scripts/common/weave.sh"
. "$DIR/scripts/common/yaml.sh"

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

exportKubeconfig() {
    cp /etc/kubernetes/admin.conf $HOME/admin.conf
    chown $SUDO_USER:$SUDO_GID $HOME/admin.conf
    chmod 444 /etc/kubernetes/admin.conf
    if ! grep -q "kubectl completion bash" /etc/profile; then
        echo 'export KUBECONFIG=/etc/kubernetes/admin.conf' >> /etc/profile
        echo "source <(kubectl completion bash)" >> /etc/profile
    fi
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
