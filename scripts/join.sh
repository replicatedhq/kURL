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

function join() {
    if [ "$MASTER" = "1" ]; then
        logStep "Join Kubernetes master node"

        # this will stop all the control plane pods except etcd
        rm -f /etc/kubernetes/manifests/kube-*
        while docker ps | grep -q kube-apiserver ; do
            sleep 2
        done
        # delete files that need to be regenerated in case of load balancer address change
        rm -f /etc/kubernetes/*.conf
        rm -f /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.key
    else
        logStep "Join Kubernetes node"
    fi

    mkdir -p "$KUBEADM_CONF_DIR"
    render_yaml kubeadm-join-config-v1beta2.yaml > "$KUBEADM_CONF_FILE"
    if [ "$MASTER" = "1" ]; then
        echo "controlPlane:" >> "$KUBEADM_CONF_FILE"
        echo "  certificateKey: $CERT_KEY" >> "$KUBEADM_CONF_FILE"
    fi

    set +e
    (set -x; kubeadm join --config /opt/replicated/kubeadm.conf --ignore-preflight-errors=all)
    _status=$?
    set -e

    if [ "$_status" -ne "0" ]; then
        printf "${RED}Failed to join the kubernetes cluster.${NC}\n" 1>&2
        exit $_status
    fi

    if [ "$MASTER" = "1" ]; then
        logStep "Master node joined successfully"
    else
        logStep "Node joined successfully"
    fi
}

outro() {
    printf "\n"
    printf "\t\t${GREEN}Installation${NC}\n"
    printf "\t\t${GREEN}  Complete ✔${NC}\n"
    if [ "$MASTER" = "1" ]; then
        printf "\n"
        printf "To access the cluster with kubectl, reload your shell:\n"
        printf "\n"
        printf "${GREEN}    bash -l${NC}\n"
    fi
    printf "\n"
}

function main() {
    export KUBECONFIG=/etc/kubernetes/admin.conf
    requireRootUser
    discover
    flags "$@"
    preflights
    joinPrompts
    prompts
    prepare
    join
    outro
}

main "$@"
