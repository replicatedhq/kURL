
function upgrade_kubernetes_patch() {
    if [ "$KUBERNETES_UPGRADE" != "1" ]; then
        return
    fi
    if [ "$KUBERNETES_UPGRADE_LOCAL_MASTER_PATCH" == "1" ]; then
        upgrade_kubernetes_local_master_patch "$KUBERNETES_VERSION"
    fi
    if [ "$KUBERNETES_UPGRADE_REMOTE_MASTERS_PATCH" == "1" ]; then
        upgrade_kubernetes_remote_masters_patch "$KUBERNETES_VERSION"
    fi
    DID_UPGRADE_KUBERNETES=1
}

function upgrade_kubernetes_local_master_patch() {
    local k8sVersion=$1
    local node=$(hostname)

    upgrade_kubeadm "$k8sVersion"
    kubeadm config migrate --old-config /opt/replicated/kubeadm.conf --new-config /opt/replicated/kubeadm.conf

    kubeadm upgrade plan "v${k8sVersion}"
    printf "${YELLOW}Drain local node and apply upgrade? ${NC}"
    confirmY
 
    disable_rook_ceph_operator
    kubernetes_drain "$node"
 
    spinner_kubernetes_api_healthy
    kubeadm upgrade apply "v$k8sVersion" --yes --config /opt/replicated/kubeadm.conf --force
    # waitForNodes
    sed -i "s/kubernetesVersion:.*/kubernetesVersion: v${k8sVersion}/" /opt/replicated/kubeadm.conf

    kubernetes_install_host_packages "$k8sVersion"
    systemctl daemon-reload
    systemctl start kubelet
    kubectl uncordon "$node"
    enable_rook_ceph_operator

    # waitForNodes
    # spinnerNodeVersion "$node" "$k8sVersion"
    # spinnerNodesReady
}

function upgrade_kubeadm() {
    local k8sVersion=$1

    if [ "$AIRGAP" != "1" ] && [ -n "$KURL_URL" ]; then
        kubernetes_get_host_packages_online "$k8sVersion"
    fi
    case "$LSB_DIST" in
        ubuntu)
            cp $DIR/packages/kubernetes/${k8sVersion}/ubuntu-${DIST_VERSION}/kubeadm /usr/bin/kubeadm
            ;;
        centos|rhel)
            cp $DIR/packages/kubernetes/${k8sVersion}rhel-7/kubeadm /usr/bin/kubeadm
            ;;
    esac
    chmod a+rx /usr/bin/kubeadm
}

function upgrade_kubernetes_remote_masters_patch() {
    k8sVersion="$1"

    semverParse "$k8sVersion"
    local upgradeMajor="$major"
    local upgradeMinor="$minor"
    local upgradePatch="$patch"

    while read -r node; do
        nodeName=$(echo "$node" | awk '{ print $1 }')
        nodeVersion="$(echo "$node" | awk '{ print $5 }' | sed 's/v//' )"
        semverParse "$nodeVersion"
        nodeMinor="$minor"
        nodePatch="$patch"
        if [ "$nodeMinor" -gt "$upgradeMinor" ]; then
            continue
        fi
        if [ "$nodeMinor" -eq "$upgradeMinor" ] && [ "$nodePatch" -ge "$upgradePatch" ]; then
            continue
        fi

        printf "${YELLOW}Drain master node $nodeName to prepare for upgrade? ${NC}"
        confirmY
        kubernetes_drain "$nodeName"

        printf "\n\n\tRun the upgrade script on remote master node to proceed: ${GREEN}$nodeName${NC}\n\n"

        if [ "$AIRGAP" = "1" ] || [ -z "$KURL_URL" ]; then
            printf "\t${GREEN}cat upgrade.sh | sudo bash -s airgap hostname-check=${nodeName} kubernetes-version=${k8sVersion}${NC}\n\n"
        else
            printf "\t${GREEN}curl $KURL_URL/node-upgrade | sudo bash -s hostname-check=${nodeName} kubernetes-version=${k8sVersion}${NC}\n\n"
        fi

        spinner_until -1 kubernetes_node_has_version "$nodeName" "$k8sVersion"
        logSuccess "Kubernetes $k8sVersion detected on $nodeName"

        kubectl uncordon "$nodeName"
    done < <(try_1m kubernetes_remote_masters)

    # spinnerNodesReady
}
