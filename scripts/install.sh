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

outro() {
    echo
    if [ -z "$PUBLIC_ADDRESS" ]; then
      if [ -z "$PRIVATE_ADDRESS" ]; then
        PUBLIC_ADDRESS="<this_server_address>"
        PRIVATE_ADDRESS="<this_server_address>"
      else
        PUBLIC_ADDRESS="$PRIVATE_ADDRESS"
      fi
    fi

    KUBEADM_TOKEN_CA_HASH=$(cat /tmp/kubeadm-init | grep 'discovery-token-ca-cert-hash' | awk '{ print $(NF) }')

    printf "\n"
    printf "\t\t${GREEN}Installation${NC}\n"
    printf "\t\t${GREEN}  Complete ✔${NC}\n"
    printf "\n"
    printf "To access the cluster with kubectl, reload your shell:\n"
    printf "\n"
    printf "${GREEN}    bash -l${NC}\n"
    printf "\n"
    if [ "$AIRGAP" -eq "1" ]; then
        printf "\n"
        printf "To add nodes to this installation, copy and unpack this bundle on your other nodes, and run the following:"
        printf "\n"
        printf "\n"
        printf "${GREEN}    cat ./kubernetes-node-join.sh | sudo bash -s airgap kubernetes-master-address=${PRIVATE_ADDRESS} kubeadm-token=${BOOTSTRAP_TOKEN} kubeadm-token-ca-hash=$KUBEADM_TOKEN_CA_HASH kubernetes-version=$KUBERNETES_VERSION \n"
        printf "${NC}"
        printf "\n"
        printf "\n"
    else
        printf "\n"
        printf "To add nodes to this installation, run the following script on your other nodes"
        printf "\n"
        printf "${GREEN}    curl {{ replicated_install_url }}/{{ kubernetes_node_join_path }} | sudo bash -s kubernetes-master-address=${PRIVATE_ADDRESS} kubeadm-token=${BOOTSTRAP_TOKEN} kubeadm-token-ca-hash=$KUBEADM_TOKEN_CA_HASH kubernetes-version=$KUBERNETES_VERSION \n"
        printf "${NC}"
        printf "\n"
        printf "\n"
    fi
}

function main() {
    export KUBECONFIG=/etc/kubernetes/admin.conf
    requireRootUser
    discover
    flags "$@"
    preflights
    prompts
    prepare
    init
    weave
    rook
    contour
    outro
}

main "$@"
