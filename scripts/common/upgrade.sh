
function upgrade_kubernetes() {

    if [ "$KUBERNETES_UPGRADE" != "1" ]; then
        enable_rook_ceph_operator
        return
    fi

    disable_rook_ceph_operator

    upgrade_kubernetes_step
    upgrade_kubernetes_minor
    upgrade_kubernetes_patch

    enable_rook_ceph_operator
}

function report_upgrade_kubernetes() {
    report_addon_start "kubernetes_upgrade" "$KUBERNETES_VERSION"
    export REPORTING_CONTEXT_INFO="kubernetes_upgrade $KUBERNETES_VERSION"
    upgrade_kubernetes
    export REPORTING_CONTEXT_INFO=""
    report_addon_success "kubernetes_upgrade" "$KUBERNETES_VERSION"
}

function upgrade_kubernetes_step() {
    if [ "$KUBERNETES_STEP_LOCAL_PRIMARY" == "1" ]; then
        upgrade_kubernetes_local_master_minor "$STEP_VERSION"
    fi
    if [ "$KUBERNETES_STEP_REMOTE_PRIMARIES" == "1" ]; then
        upgrade_kubernetes_remote_masters_minor "$STEP_VERSION"
    fi
    if [ "$KUBERNETES_STEP_SECONDARIES" == "1" ]; then
        upgrade_kubernetes_workers_minor "$STEP_VERSION"
    fi
}

function upgrade_kubernetes_minor() {
    if [ "$KUBERNETES_UPGRADE_LOCAL_PRIMARY_MINOR" == "1" ]; then
        upgrade_kubernetes_local_master_minor "$KUBERNETES_VERSION"
    fi
    if [ "$KUBERNETES_UPGRADE_REMOTE_PRIMARIES_MINOR" == "1" ]; then
        upgrade_kubernetes_remote_masters_minor "$KUBERNETES_VERSION"
    fi
    if [ "$KUBERNETES_UPGRADE_SECONDARIES_MINOR" == "1" ]; then
        upgrade_kubernetes_workers_minor "$KUBERNETES_VERSION"
    fi
}


function upgrade_kubernetes_patch() {
    if [ "$KUBERNETES_UPGRADE_LOCAL_PRIMARY_PATCH" == "1" ]; then
        upgrade_kubernetes_local_master_patch "$KUBERNETES_VERSION"
    fi
    if [ "$KUBERNETES_UPGRADE_REMOTE_PRIMARIES_PATCH" == "1" ]; then
        upgrade_kubernetes_remote_masters_patch "$KUBERNETES_VERSION"
    fi
    if [ "$KUBERNETES_UPGRADE_SECONDARIES_PATCH" == "1" ]; then
        upgrade_kubernetes_workers_patch "$KUBERNETES_VERSION"
    fi
}

function upgrade_kubernetes_local_master_patch() {
    local k8sVersion="$1"
    local node="$(get_local_node_name)"
    local upgrading_kubernetes=true

    logStep "Upgrading Kubernetes to version $k8sVersion"

    load_images "$DIR/packages/kubernetes/$k8sVersion/images"
    if [ -n "$SONOBUOY_VERSION" ] && [ -d "$DIR/packages/kubernetes-conformance/$k8sVersion/images" ]; then
        load_images "$DIR/packages/kubernetes-conformance/$k8sVersion/images"
    fi

    upgrade_kubeadm "$k8sVersion"

    ( set -x; kubeadm upgrade plan "v${k8sVersion}" )
    printf "${YELLOW}Drain local node and apply upgrade? ${NC}"
    confirmY
    kubernetes_drain "$node"

    maybe_patch_node_cri_socket_annotation "$node"
 
    spinner_kubernetes_api_stable
    # ignore-preflight-errors, do not fail on fail to pull images for airgap
    ( set -x; kubeadm upgrade apply "v$k8sVersion" --yes --force --ignore-preflight-errors=all )

    kubernetes_install_host_packages "$k8sVersion"
    systemctl daemon-reload
    systemctl restart kubelet

    spinner_kubernetes_api_stable
    kubectl uncordon "$node"
    upgrade_delete_node_flannel "$node"

    spinner_until 120 kubernetes_node_has_version "$node" "$k8sVersion"
    spinner_until 120 kubernetes_all_nodes_ready

    logSuccess "Kubernetes upgraded to version $k8sVersion"
}

function upgrade_kubeadm() {
    local k8sVersion=$1

    upgrade_maybe_remove_kubeadm_network_plugin_flag "$k8sVersion"

    cp -f "$DIR/packages/kubernetes/${k8sVersion}/assets/kubeadm" /usr/bin/
    chmod a+rx /usr/bin/kubeadm
}

function upgrade_kubernetes_remote_masters_patch() {
    while read -r master; do
        upgrade_kubernetes_remote_node_patch "$master"
    done < <(try_1m kubernetes_remote_masters)

    spinner_until 120 kubernetes_all_nodes_ready
}

function upgrade_kubernetes_workers_patch() {
    while read -r worker; do
        upgrade_kubernetes_remote_node_patch "$worker"
    done < <(try_1m kubernetes_workers)
}

function upgrade_kubernetes_remote_node_patch() {
    # one line of output from `kubectl get nodes`
    local node="$1"
    nodeName=$(echo "$node" | awk '{ print $1 }')
    nodeVersion="$(echo "$node" | awk '{ print $5 }' | sed 's/v//' )"
    semverParse "$nodeVersion"
    nodeMinor="$minor"
    nodePatch="$patch"
    if [ "$nodeMinor" -gt "$KUBERNETES_TARGET_VERSION_MINOR" ]; then
        return
    elif [ "$nodeMinor" -eq "$KUBERNETES_TARGET_VERSION_MINOR" ] && [ "$nodePatch" -ge "$KUBERNETES_TARGET_VERSION_PATCH" ]; then
        return
    fi

    DOCKER_REGISTRY_IP=$(kubectl -n kurl get service registry -o=jsonpath='{@.spec.clusterIP}' 2>/dev/null || echo "")

    printf "\n${YELLOW}Drain node $nodeName to prepare for upgrade? ${NC}"
    confirmY
    kubernetes_drain "$nodeName"

    local common_flags
    common_flags="${common_flags}$(get_docker_registry_ip_flag "${DOCKER_REGISTRY_IP}")"
    common_flags="${common_flags}$(get_additional_no_proxy_addresses_flag "${NO_PROXY_ADDRESSES}" "${NO_PROXY_ADDRESSES}")"
    common_flags="${common_flags}$(get_kurl_install_directory_flag "${KURL_INSTALL_DIRECTORY_FLAG}")"

    printf "\n\n\tRun the upgrade script on remote node to proceed: ${GREEN}$nodeName${NC}\n\n"

    if [ "$AIRGAP" = "1" ]; then
        printf "\t${GREEN}cat ./upgrade.sh | sudo bash -s airgap kubernetes-version=${KUBERNETES_VERSION}${common_flags}${NC}\n\n"
    else
        local prefix=
        prefix="$(build_installer_prefix "${INSTALLER_ID}" "${KURL_VERSION}" "${KURL_URL}" "${PROXY_ADDRESS}")"

        printf "\t${GREEN} ${prefix}upgrade.sh | sudo bash -s kubernetes-version=${KUBERNETES_VERSION}${common_flags}${NC}\n\n"
    fi

    spinner_until -1 kubernetes_node_has_version "$nodeName" "$KUBERNETES_VERSION"
    logSuccess "Kubernetes $KUBERNETES_VERSION detected on $nodeName"

    kubectl uncordon "$nodeName"
    upgrade_delete_node_flannel "$nodeName"
}

function upgrade_kubernetes_local_master_minor() {
    local k8sVersion="$1"
    local node="$(get_local_node_name)"
    local upgrading_kubernetes=true

    logStep "Upgrading Kubernetes to version $k8sVersion"

    load_images "$DIR/packages/kubernetes/$k8sVersion/images"
    if [ -n "$SONOBUOY_VERSION" ] && [ -d "$DIR/packages/kubernetes-conformance/$k8sVersion/images" ]; then
        load_images "$DIR/packages/kubernetes-conformance/$k8sVersion/images"
    fi

    upgrade_kubeadm "$k8sVersion"

    ( set -x; kubeadm upgrade plan "v${k8sVersion}" )
    printf "${YELLOW}Drain local node and apply upgrade? ${NC}"
    confirmY
    kubernetes_drain "$node"

    maybe_patch_node_cri_socket_annotation "$node"

    spinner_kubernetes_api_stable
    # ignore-preflight-errors, do not fail on fail to pull images for airgap
    ( set -x; kubeadm upgrade apply "v$k8sVersion" --yes --force --ignore-preflight-errors=all )
    upgrade_etcd_image_18 "$k8sVersion"

    kubernetes_install_host_packages "$k8sVersion"
    systemctl daemon-reload
    systemctl restart kubelet

    spinner_kubernetes_api_stable
    kubectl uncordon "$node"
    upgrade_delete_node_flannel "$node"

    # force deleting the cache because the api server will use the stale API versions after kubeadm upgrade
    rm -rf $HOME/.kube

    spinner_until 120 kubernetes_node_has_version "$node" "$k8sVersion"
    spinner_until 120 kubernetes_all_nodes_ready

    logSuccess "Kubernetes upgraded to version $k8sVersion"
}

function upgrade_kubernetes_remote_masters_minor() {
    local k8sVersion="$1"
    while read -r master; do
        upgrade_kubernetes_remote_node_minor "$master" "$k8sVersion"
    done < <(try_1m kubernetes_remote_masters)
    spinner_until 120 kubernetes_all_nodes_ready
}

function upgrade_kubernetes_workers_minor() {
    local k8sVersion="$1"
    while read -r worker; do
        upgrade_kubernetes_remote_node_minor "$worker" "$k8sVersion"
    done < <(try_1m kubernetes_workers)
}

function upgrade_kubernetes_remote_node_minor() {
    # one line of output from `kubectl get nodes`
    local node="$1"
    local targetK8sVersion="$2"

    nodeName=$(echo "$node" | awk '{ print $1 }')
    nodeVersion="$(echo "$node" | awk '{ print $5 }' | sed 's/v//' )"
    semverParse "$nodeVersion"
    nodeMinor="$minor"
    nodePatch="$patch"

    semverParse "$targetK8sVersion"
    local targetMinor="$minor"
    local targetPatch="$patch"

    if [ "$nodeMinor" -ge "$targetMinor" ]; then
        return 0
    fi

    DOCKER_REGISTRY_IP=$(kubectl -n kurl get service registry -o=jsonpath='{@.spec.clusterIP}' 2>/dev/null || echo "")

    printf "\n${YELLOW}Drain node $nodeName to prepare for upgrade? ${NC}"
    confirmY
    kubernetes_drain "$nodeName"

    local common_flags
    common_flags="${common_flags}$(get_docker_registry_ip_flag "${DOCKER_REGISTRY_IP}")"
    common_flags="${common_flags}$(get_additional_no_proxy_addresses_flag "${NO_PROXY_ADDRESSES}" "${NO_PROXY_ADDRESSES}")"
    common_flags="${common_flags}$(get_kurl_install_directory_flag "${KURL_INSTALL_DIRECTORY_FLAG}")"
    common_flags="${common_flags}$(get_remotes_flags)"

    printf "\n\n\tRun the upgrade script on remote node to proceed: ${GREEN}$nodeName${NC}\n\n"

    if [ "$AIRGAP" = "1" ]; then
        printf "\t${GREEN}cat ./upgrade.sh | sudo bash -s airgap kubernetes-version=${targetK8sVersion}${common_flags}${NC}\n\n"
    else
        local prefix=
        prefix="$(build_installer_prefix "${INSTALLER_ID}" "${KURL_VERSION}" "${KURL_URL}" "${PROXY_ADDRESS}")"

        printf "\t${GREEN} ${prefix}upgrade.sh | sudo bash -s kubernetes-version=${targetK8sVersion}${common_flags}${NC}\n\n"
    fi

    rm -rf $HOME/.kube

    spinner_until -1 kubernetes_node_has_version "$nodeName" "$targetK8sVersion"
    logSuccess "Kubernetes $targetK8sVersion detected on $nodeName"

    kubectl uncordon "$nodeName"
    upgrade_delete_node_flannel "$nodeName"
    spinner_until 120 kubernetes_all_nodes_ready
}

# In k8s 1.18 the etcd image tag changed from 3.4.3 to 3.4.3-0 but kubeadm does not rewrite the
# etcd manifest to use the new tag. When kubeadm init is run after the upgrade it switches to the
# tag and etcd takes a few minutes to restart, which often results in kubeadm init failing. This
# forces use of the updated tag so that the restart of etcd happens during upgrade when the node is
# already drained
function upgrade_etcd_image_18() {
    semverParse "$1"
    if [ "$minor" != "18" ]; then
        return 0
    fi
    local etcd_tag=$(kubeadm config images list 2>/dev/null | grep etcd | awk -F':' '{ print $NF }')
    sed -i "s/image: k8s.gcr.io\/etcd:.*/image: k8s.gcr.io\/etcd:$etcd_tag/" /etc/kubernetes/manifests/etcd.yaml
}

# Workaround to fix "kubeadm upgrade node" error:
#   "error execution phase preflight: docker is required for container runtime: exec: "docker": executable file not found in $PATH"
# See https://github.com/kubernetes/kubeadm/issues/2364
function maybe_patch_node_cri_socket_annotation() {
    local node="$1"

    if [ -n "$DOCKER_VERSION" ] || [ -z "$CONTAINERD_VERSION" ]; then
        return
    fi

    if kubectl get node "$node" -ojsonpath='{.metadata.annotations.kubeadm\.alpha\.kubernetes\.io/cri-socket}' | grep -q "dockershim.sock" ; then
        kubectl annotate node "$node" --overwrite "kubeadm.alpha.kubernetes.io/cri-socket=unix:///run/containerd/containerd.sock"
    fi
}

# When there has been a migration from Docker to Containerd the kubeadm-flags.env file may contain
# the flag "--network-plugin" which has been removed as of Kubernetes 1.24 and causes the Kubelet
# to fail with "Error: failed to parse kubelet flag: unknown flag: --network-plugin". This function
# will remove the erroneous flag from the file.
function upgrade_maybe_remove_kubeadm_network_plugin_flag() {
    local k8sVersion=$1
    if [ "$(kubernetes_version_minor "$k8sVersion")" -lt "24" ]; then
        return
    fi
    sed -i 's/ \?--network-plugin \?[^ "]*//' /var/lib/kubelet/kubeadm-flags.env
}

# delete the flannel pod on the node so that CNI plugin binaries are recreated
# workaround for https://github.com/kubernetes/kubernetes/issues/115629
function upgrade_delete_node_flannel() {
    local node="$1"

    if kubectl get ns 2>/dev/null | grep -q kube-flannel; then
        kubectl delete pod -n kube-flannel --field-selector="spec.nodeName=$node"
    fi
}
