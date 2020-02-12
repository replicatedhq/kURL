#!/bin/bash

set -e

DIR=.

# Magic begin: scripts are inlined for distribution. See "make build/join.sh"
. $DIR/scripts/Manifest
. $DIR/scripts/common/addon.sh
. $DIR/scripts/common/common.sh
. $DIR/scripts/common/discover.sh
. $DIR/scripts/common/docker.sh
. $DIR/scripts/common/flags.sh
. $DIR/scripts/common/kubernetes.sh
. $DIR/scripts/common/object_store.sh
. $DIR/scripts/common/preflights.sh
. $DIR/scripts/common/prompts.sh
. $DIR/scripts/common/proxy.sh
. $DIR/scripts/common/rook.sh
. $DIR/scripts/common/yaml.sh
. $DIR/scripts/common/coredns.sh
# Magic end

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

    kustomize_kubeadm_join=./kustomize/kubeadm/join
    if [ "$MASTER" = "1" ]; then
        insert_patches_strategic_merge \
            $kustomize_kubeadm_join/kustomization.yaml \
            patch-certificate-key.yaml
    fi
    # Add kubeadm join patches from addons.
    for patch in $(ls -1 ${kustomize_kubeadm_join}-patches/* 2>/dev/null || echo); do
        patch_basename="$(basename $patch)"
        cp $patch $kustomize_kubeadm_join/$patch_basename
        insert_patches_strategic_merge \
            $kustomize_kubeadm_join/kustomization.yaml \
            $patch_basename
    done
    mkdir -p "$KUBEADM_CONF_DIR"
    kubectl kustomize $kustomize_kubeadm_join > $KUBEADM_CONF_DIR/kubeadm-join-raw.yaml
    render_yaml_file $KUBEADM_CONF_DIR/kubeadm-join-raw.yaml > $KUBEADM_CONF_FILE

    cp $KUBEADM_CONF_FILE $KUBEADM_CONF_DIR/kubeadm_conf_copy_in
    docker run -i --rm -v $KUBEADM_CONF_DIR:/home/ --entrypoint /bin/bash replicated/kurl-util:v2020.02.11-0 \
        -c "/usr/local/bin/yamlutil -r -fp /home/kubeadm_conf_copy_in -yf metadata"
    mv $KUBEADM_CONF_DIR/kubeadm_conf_copy_in $KUBEADM_CONF_FILE

    set +e
    (set -x; kubeadm join --config /opt/replicated/kubeadm.conf --ignore-preflight-errors=all)
    _status=$?
    set -e

    if [ "$_status" -ne "0" ]; then
        printf "${RED}Failed to join the kubernetes cluster.${NC}\n" 1>&2
        exit $_status
    fi

    if [ "$MASTER" = "1" ]; then
        exportKubeconfig
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
    flags $FLAGS
    flags "$@"
    preflights
    joinPrompts
    prompts
    configure_proxy
    install_docker
    get_shared
    setup_kubeadm_kustomize
    addon_join aws "$AWS_VERSION"
    addon_join nodeless "$NODELESS_VERSION"
    addon_join calico "$CALICO_VERSION"
    addon_join weave "$WEAVE_VERSION"
    addon_join rook "$ROOK_VERSION"
    addon_join openebs "$OPENEBS_VERSION"
    addon_join minio "$MINIO_VERSION"
    addon_join contour "$CONTOUR_VERSION"
    addon_join registry "$REGISTRY_VERSION"
    addon_join prometheus "$PROMETHEUS_VERSION"
    addon_join kotsadm "$KOTSADM_VERSION"
    addon_join velero "$VELERO_VERSION"
    addon_join fluentd "$FLUENTD_VERSION"
    kubernetes_host
    join
    outro
}

main "$@"
