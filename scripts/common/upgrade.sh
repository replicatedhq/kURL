
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
#    trap 'addon_install_fail_nobundle "kubernetes_upgrade" "$KUBERNETES_VERSION"' ERR
    upgrade_kubernetes
#    trap - ERR
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
    local k8sVersion=$1
    local node=$(hostname)

    load_images $DIR/packages/kubernetes/$k8sVersion/images
    upgrade_kubeadm "$k8sVersion"

    kubeadm upgrade plan "v${k8sVersion}"
    printf "${YELLOW}Drain local node and apply upgrade? ${NC}"
    confirmY " "
 
    kubernetes_drain "$node"
 
    spinner_kubernetes_api_stable
    kubeadm upgrade apply "v$k8sVersion" --yes --force

    kubernetes_install_host_packages "$k8sVersion"
    systemctl daemon-reload
    systemctl restart kubelet

    spinner_kubernetes_api_stable
    kubectl uncordon "$node"

    spinner_until 120 kubernetes_node_has_version "$node" "$k8sVersion"
    spinner_until 120 kubernetes_nodes_ready
}

function upgrade_kubeadm() {
    local k8sVersion=$1

    if [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        kubernetes_get_host_packages_online "$k8sVersion"
    fi
    case "$LSB_DIST" in
        ubuntu)
            cp $DIR/packages/kubernetes/${k8sVersion}/ubuntu-${DIST_VERSION}/kubeadm /usr/bin/kubeadm
            ;;
        centos|rhel|amzn)
            cp $DIR/packages/kubernetes/${k8sVersion}/rhel-7/kubeadm /usr/bin/kubeadm
            ;;
    esac
    chmod a+rx /usr/bin/kubeadm
}

function upgrade_kubernetes_remote_masters_patch() {
    while read -r master; do
        upgrade_kubernetes_remote_node_patch "$master"
    done < <(try_1m kubernetes_remote_masters)

    spinner_until 120 kubernetes_nodes_ready
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
        continue
    fi
    if [ "$nodeMinor" -eq "$KUBERNETES_TARGET_VERSION_MINOR" ] && [ "$nodePatch" -ge "$KUBERNETES_TARGET_VERSION_PATCH" ]; then
        continue
    fi

    DOCKER_REGISTRY_IP=$(kubectl -n kurl get service registry -o=jsonpath='{@.spec.clusterIP}' 2>/dev/null || echo "")

    printf "${YELLOW}Drain node $nodeName to prepare for upgrade? ${NC}"
    confirmY " "
    kubernetes_drain "$nodeName"

    local common_flags
    common_flags="${common_flags}$(get_docker_registry_ip_flag "${DOCKER_REGISTRY_IP}")"
    common_flags="${common_flags}$(get_additional_no_proxy_addresses_flag "${NO_PROXY_ADDRESSES}" "${NO_PROXY_ADDRESSES}")"
    common_flags="${common_flags}$(get_kurl_install_directory_flag "${KURL_INSTALL_DIRECTORY_FLAG}")"
    printf "\n\n\tRun the upgrade script on remote node to proceed: ${GREEN}$nodeName${NC}\n\n"

    if [ "$AIRGAP" = "1" ]; then
        printf "\t${GREEN}cat upgrade.sh | sudo bash -s airgap kubernetes-version=${KUBERNETES_VERSION}${common_flags}${NC}\n\n"
    elif [ -z "$KURL_URL" ]; then
        printf "\t${GREEN}cat upgrade.sh | sudo bash -s kubernetes-version=${KUBERNETES_VERSION}${common_flags}${NC}\n\n"
    else
        local prefix="curl $KURL_URL/$INSTALLER_ID/"
        if [ -z "$KURL_URL" ]; then
            prefix="cat "
        fi
        printf "\t${GREEN} ${prefix}upgrade.sh | sudo bash -s kubernetes-version=${KUBERNETES_VERSION}${common_flags}${NC}\n\n"
    fi

    spinner_until -1 kubernetes_node_has_version "$nodeName" "$KUBERNETES_VERSION"
    logSuccess "Kubernetes $KUBERNETES_VERSION detected on $nodeName"

    kubectl uncordon "$nodeName"
}

function upgrade_kubernetes_local_master_minor() {
    local k8sVersion=$1
    local node=$(hostname)

    load_images $DIR/packages/kubernetes/$k8sVersion/images
    upgrade_kubeadm "$k8sVersion"

    kubeadm upgrade plan "v${k8sVersion}"
    printf "${YELLOW}Drain local node and apply upgrade? ${NC}"
    confirmY " "

    kubernetes_drain "$node"

    spinner_kubernetes_api_stable
    kubeadm upgrade apply "v$k8sVersion" --yes --force
    upgrade_etcd_image_18 "$k8sVersion"

    kubernetes_install_host_packages "$k8sVersion"
    systemctl daemon-reload
    systemctl restart kubelet

    spinner_kubernetes_api_stable
    kubectl uncordon "$node"

    # force deleting the cache because the api server will use the stale API versions after kubeadm upgrade
    rm -rf $HOME/.kube

    spinner_until 120 kubernetes_node_has_version "$node" "$k8sVersion"
    spinner_until 120 kubernetes_nodes_ready
}

function upgrade_kubernetes_remote_masters_minor() {
    local k8sVersion="$1"
    while read -r master; do
        upgrade_kubernetes_remote_node_minor "$master" "$k8sVersion"
    done < <(try_1m kubernetes_remote_masters)
    spinner_until 120 kubernetes_nodes_ready
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
        continue
    fi

    DOCKER_REGISTRY_IP=$(kubectl -n kurl get service registry -o=jsonpath='{@.spec.clusterIP}' 2>/dev/null || echo "")

    printf "${YELLOW}Drain node $nodeName to prepare for upgrade? ${NC}"
    confirmY " "
    kubernetes_drain "$nodeName"

    local common_flags
    common_flags="${common_flags}$(get_docker_registry_ip_flag "${DOCKER_REGISTRY_IP}")"
    common_flags="${common_flags}$(get_additional_no_proxy_addresses_flag "${NO_PROXY_ADDRESSES}" "${NO_PROXY_ADDRESSES}")"
    common_flags="${common_flags}$(get_kurl_install_directory_flag "${KURL_INSTALL_DIRECTORY_FLAG}")"


    printf "\n\n\tRun the upgrade script on remote node to proceed: ${GREEN}$nodeName${NC}\n\n"

    if [ "$AIRGAP" = "1" ]; then
        printf "\t${GREEN}cat upgrade.sh | sudo bash -s airgap kubernetes-version=${targetK8sVersion}${common_flags}${NC}\n\n"
    elif [ -z "$KURL_URL" ]; then
        printf "\t${GREEN}cat upgrade.sh | sudo bash -s kubernetes-version=${targetK8sVersion}${common_flags}${NC}\n\n"
    else
        local prefix="curl $KURL_URL/$INSTALLER_ID/"
        if [ -z "$KURL_URL" ]; then
            prefix="cat "
        fi
        printf "\t${GREEN} ${prefix}upgrade.sh | sudo bash -s kubernetes-version=${targetK8sVersion}${common_flags}${NC}\n\n"
    fi

    rm -rf $HOME/.kube

    spinner_until -1 kubernetes_node_has_version "$nodeName" "$targetK8sVersion"
    logSuccess "Kubernetes $targetK8sVersion detected on $nodeName"

    kubectl uncordon "$nodeName"
    spinner_until 120 kubernetes_nodes_ready
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
