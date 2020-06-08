function upgrade_kubernetes() {

    if [ "$KUBERNETES_UPGRADE" != "1" ]; then
        return
    fi

    upgrade_kubernetes_minor

    if [ "$DID_UPGRADE_KUBERNETES" == 1 ]; then
        return
    fi

    upgrade_kubernetes_patch
}

function upgrade_kubernetes_minor() {
    if [ "$KUBERNETES_UPGRADE_LOCAL_MASTER_MINOR" == "1" ]; then
        upgrade_kubernetes_local_master_minor "$KUBERNETES_VERSION"
    fi
    if [ "$KUBERNETES_UPGRADE_REMOTE_MASTERS_MINOR" == "1" ]; then
        upgrade_kubernetes_remote_masters_minor "$KUBERNETES_VERSION"
    fi
    if [ "$KUBERNETES_UPGRADE_WORKERS_MINOR" == "1" ]; then
        upgrade_kubernetes_workers_minor "$KUBERNETES_VERSION"
    fi

    DID_UPGRADE_KUBERNETES=1
}


function upgrade_kubernetes_patch() {
    if [ "$KUBERNETES_UPGRADE_LOCAL_MASTER_PATCH" == "1" ]; then
        upgrade_kubernetes_local_master_patch "$KUBERNETES_VERSION"
    fi
    if [ "$KUBERNETES_UPGRADE_REMOTE_MASTERS_PATCH" == "1" ]; then
        upgrade_kubernetes_remote_masters_patch "$KUBERNETES_VERSION"
    fi
    if [ "$KUBERNETES_UPGRADE_WORKERS_PATCH" == "1" ]; then
        upgrade_kubernetes_workers_patch "$KUBERNETES_VERSION"
    fi

    DID_UPGRADE_KUBERNETES=1
}

function upgrade_kubernetes_local_master_patch() {
    local k8sVersion=$1
    local node=$(hostname)

    load_images $DIR/packages/kubernetes/$k8sVersion/images
    upgrade_kubeadm "$k8sVersion"
    kubeadm config migrate --old-config /opt/replicated/kubeadm.conf --new-config /opt/replicated/kubeadm.conf

    kubeadm upgrade plan "v${k8sVersion}"
    printf "${YELLOW}Drain local node and apply upgrade? ${NC}"
    confirmY
 
    disable_rook_ceph_operator
    kubernetes_drain "$node"
 
    spinner_kubernetes_api_healthy
    kubeadm upgrade apply "v$k8sVersion" --yes --config /opt/replicated/kubeadm.conf --force
    sed -i "s/kubernetesVersion:.*/kubernetesVersion: v${k8sVersion}/" /opt/replicated/kubeadm.conf

    kubernetes_install_host_packages "$k8sVersion"
    systemctl daemon-reload
    systemctl restart kubelet
    spinner_kubernetes_api_healthy
    kubectl uncordon "$node"

    enable_rook_ceph_operator

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

    printf "${YELLOW}Drain node $nodeName to prepare for upgrade? ${NC}"
    confirmY
    kubernetes_drain "$nodeName"

    printf "\n\n\tRun the upgrade script on remote node to proceed: ${GREEN}$nodeName${NC}\n\n"

    if [ "$AIRGAP" = "1" ] || [ -z "$KURL_URL" ]; then
        printf "\t${GREEN}cat upgrade.sh | sudo bash -s airgap hostname-check=${nodeName} kubernetes-version=${KUBERNETES_VERSION}${NC}\n\n"
    else
        local prefix="curl $KURL_URL/$INSTALLER_ID/"
        if [ -z "$KURL_URL" ]; then
            prefix="cat "
        fi
        printf "\t${GREEN} ${prefix}upgrade.sh | sudo bash -s hostname-check=${nodeName} kubernetes-version=${KUBERNETES_VERSION}${NC}\n\n"
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

    kubeadm config migrate --old-config /opt/replicated/kubeadm.conf --new-config /opt/replicated/kubeadm.conf

    kubectl -n kube-system get configmaps kube-proxy -o yaml > /tmp/temp.yaml
    $DIR/bin/yamlutil -p -fp /tmp/temp.yaml -yp data_config.conf

    cat >> /opt/replicated/kubeadm.conf <<EOF
---
EOF
    cat /tmp/temp.yaml >> /opt/replicated/kubeadm.conf

    rm /tmp/temp.yaml

    kubeadm upgrade plan "v${k8sVersion}"
    printf "${YELLOW}Drain local node and apply upgrade? ${NC}"
    confirmY " "

    disable_rook_ceph_operator
    
    local nodeNumber=$(($(kubectl get nodes | wc -l) - 1))
    if [ "$nodeNumber" != "1" ]; then
        disable_coredns
    fi

    spinner_kubernetes_api_healthy
    kubeadm upgrade apply "v$k8sVersion" --yes --config /opt/replicated/kubeadm.conf --force
    sed -i "s/kubernetesVersion:.*/kubernetesVersion: v${k8sVersion}/" /opt/replicated/kubeadm.conf

    kubernetes_install_host_packages "$k8sVersion"
    systemctl daemon-reload
    systemctl restart kubelet

    spinner_kubernetes_api_healthy
    kubectl uncordon "$node"

    # force deleting the cache because the api server will use the stale API versions after kubeadm upgrade
    rm -rf $HOME/.kube

    if [ "$nodeNumber" != "1" ]; then
        enable_coredns
    fi
    enable_rook_ceph_operator

    spinner_until 120 kubernetes_node_has_version "$node" "$k8sVersion"
    spinner_until 120 kubernetes_nodes_ready
}

function upgrade_kubernetes_remote_masters_minor() {
    while read -r master; do
        upgrade_kubernetes_remote_node_minor "$master"
    done < <(try_1m kubernetes_remote_masters)
    spinner_until 120 kubernetes_nodes_ready
}

function upgrade_kubernetes_workers_minor() {
    while read -r worker; do
        upgrade_kubernetes_remote_node_minor "$worker"
    done < <(try_1m kubernetes_workers)
}

function upgrade_kubernetes_remote_node_minor() {
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

    printf "${YELLOW}Drain node $nodeName to prepare for upgrade? ${NC}"
    confirmY
    kubernetes_drain "$nodeName"

    printf "\n\n\tRun the upgrade script on remote node to proceed: ${GREEN}$nodeName${NC}\n\n"

    if [ "$AIRGAP" = "1" ] || [ -z "$KURL_URL" ]; then
        printf "\t${GREEN}cat upgrade.sh | sudo bash -s airgap hostname-check=${nodeName} kubernetes-version=${KUBERNETES_VERSION}${NC}\n\n"
    else
        local prefix="curl $KURL_URL/$INSTALLER_ID/"
        if [ -z "$KURL_URL" ]; then
            prefix="cat "
        fi
        printf "\t${GREEN} ${prefix}upgrade.sh | sudo bash -s hostname-check=${nodeName} kubernetes-version=${KUBERNETES_VERSION}${NC}\n\n"
    fi

    rm -rf $HOME/.kube

    spinner_until -1 kubernetes_node_has_version "$nodeName" "$KUBERNETES_VERSION"
    logSuccess "Kubernetes $KUBERNETES_VERSION detected on $nodeName"

    kubectl uncordon "$nodeName"
}
