#!/bin/bash

export POD_CIDR
export POD_CIDR_RANGE
export POD_CIDR_IPV6
export EXISTING_POD_CIDR

export FLANNEL_ENABLE_IPV4=${FLANNEL_ENABLE_IPV4:-true}
export FLANNEL_ENABLE_IPV6=${FLANNEL_ENABLE_IPV6:-false} # TODO: support ipv6
export FLANNEL_BACKEND=${FLANNEL_BACKEND:-vxlan} # TODO: support encryption
export FLANNEL_IFACE=${FLANNEL_IFACE:-}

function flannel_pre_init() {
    local src="$DIR/addons/flannel/$FLANNEL_VERSION"
    local dst="$DIR/kustomize/flannel"

    if [ -n "$DOCKER_VERSION" ]; then
        bail "Flannel is not compatible with the Docker runtime, Containerd is required"
    fi

    if flannel_antrea_conflict ; then
        bail "Migrations from Antrea to Flannel are not supported"
    fi

    # TODO: support ipv6
    local private_address_iface=
    local default_gateway_iface=
    private_address_iface=$("$BIN_KURL" netutil iface-from-ip "$PRIVATE_ADDRESS")
    default_gateway_iface=$("$BIN_KURL" netutil default-gateway-iface)
    # if the private address is on a different interface than the default gateway, use the private address interface
    if [ -n "$private_address_iface" ] && [ "$private_address_iface" != "$default_gateway_iface" ]; then
        FLANNEL_IFACE="$private_address_iface"
    fi

    flannel_init_pod_subnet

    if flannel_weave_conflict; then
        logWarn "The migration from Weave to Flannel will require whole-cluster downtime."
        logWarn "Would you like to continue?"
        if ! confirmY ; then
            bail "Not migrating from Weave to Flannel"
        fi
        flannel_check_nodes_connectivity
        flannel_check_rook_ceph_status
    fi
}

function flannel_check_rook_ceph_status() {
    if kubectl get namespace/rook-ceph ; then
       logStep "Checking Rook Status prior migrate from Weave to Flannel"
       if ! "$DIR"/bin/kurl rook wait-for-health 300 ; then
           kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
           bail "Failed to verify Rook, Ceph is not healthy. The migration from Weave to Flannel can not be performed"
           bail "Please, ensure that Rook Ceph is healthy."
       fi
       logSuccess "Rook Ceph is healthy"
    fi
}


# flannel_check_nodes_connectivity verifies that all nodes in the cluster can reach each other through
# port 8472/UDP (this communication is a flannel requirement).
function flannel_check_nodes_connectivity() {
    local node_count
    node_count="$(kubectl get nodes --no-headers 2>/dev/null | wc -l)"
    if [ "$node_count" = "1" ]; then
        return 0
    fi

    # if we are in an airgap environment we need to load the kurl-util image locally. this
    # image has already been loaded in all remote nodes after the common_prompts function.
    if [ "$AIRGAP" = "1" ] && [ -f shared/kurl-util.tar ]; then
        if node_is_using_docker ; then
            docker load < shared/kurl-util.tar
        else
            ctr -a "$(${K8S_DISTRO}_get_containerd_sock)" -n=k8s.io images import shared/kurl-util.tar
        fi
    fi

    log "Verifying if all nodes can communicate with each other through port 8472/UDP."
    if ! "$DIR"/bin/kurl netutil nodes-connectivity --port 8472 --image "$KURL_UTIL_IMAGE" --proto udp; then
        logFail "Flannel requires UDP port 8472 for communication between nodes."
        logFail "Please make sure this port is open prior to running this upgrade."
        bail "Not migrating from Weave to Flannel"
    fi
}

function flannel_join() {
    logWarn "Flannel requires UDP port 8472 for communication between nodes."
    logWarn "Failure to open this port will cause connection failures between containers on different nodes."
}

function flannel() {
    local src="$DIR/addons/flannel/$FLANNEL_VERSION"
    local dst="$DIR/kustomize/flannel"

    cp "$src"/yaml/* "$dst/"

    # Kubernetes 1.27 uses kustomize v5 which dropped support for old, legacy style patches
    # See: https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.27.md#changelog-since-v1270
    kubernetes_kustomize_config_migrate "$dst"

    flannel_render_config

    if flannel_weave_conflict; then
        weave_to_flannel
    else
        kubectl -n kube-flannel apply -k "$dst/"
    fi

    # We will remove the flannel pods to let it be re-created
    # in order to workaround the issue scenario described in
    # https://github.com/flannel-io/flannel/issues/1721
    if [ "$KUBERNETES_UPGRADE" == "1" ]; then
       log "Restarting kube-flannel pods"
       kubectl rollout restart --namespace=kube-flannel daemonset/kube-flannel-ds
    fi

    flannel_ready_spinner
    check_network
}

function flannel_init_pod_subnet() {
    POD_CIDR="$FLANNEL_POD_CIDR"
    POD_CIDR_RANGE="$FLANNEL_POD_CIDR_RANGE"

    cp "$src/kubeadm.yaml" "$DIR/kustomize/kubeadm/init-patches/flannel.yaml"

    if commandExists kubectl; then
        EXISTING_POD_CIDR=$(kubectl -n kube-system get cm kubeadm-config -oyaml 2>/dev/null | grep podSubnet | awk '{ print $NF }')
    fi
}

function flannel_render_config() {
    render_yaml_file_2 "$src/template/kube-flannel-cfg.patch.tmpl.yaml" > "$dst/kube-flannel-cfg.patch.yaml"

    if [ "$FLANNEL_ENABLE_IPV6" = "true" ] && [ -n "$POD_CIDR_IPV6" ]; then
        render_yaml_file_2 "$src/template/ipv6.patch.tmpl.yaml" > "$dst/ipv6.patch.yaml"
        insert_patches_strategic_merge "$dst/kustomization.yaml" ipv6.patch.yaml
    fi

    if [ -n "$FLANNEL_IFACE" ]; then
        render_yaml_file_2 "$src/template/iface.patch.tmpl.yaml" > "$dst/iface.patch.yaml"
        insert_patches_json_6902 "$dst/kustomization.yaml" iface.patch.yaml apps v1 DaemonSet kube-flannel-ds kube-flannel
    fi
}

function flannel_health_check() {
    local health=
    health="$(kubectl -n kube-flannel get pods -l app=flannel -o jsonpath="{range .items[*]}{range .status.conditions[*]}{ .type }={ .status }{'\n'}{end}{end}" 2>/dev/null)"
    if echo "$health" | grep -q '^Ready=False' ; then
        return 1
    fi
    return 0
}

function flannel_ready_spinner() {
    echo "Waiting up to 5 minutes for Flannel to become healthy"
    if ! spinner_until 300 flannel_health_check; then
        kubectl logs -n kube-flannel -l app=flannel --all-containers --tail 10 || true
        bail "The Flannel add-on failed to deploy successfully."
    fi
}

function flannel_weave_conflict() {
    ls /etc/cni/net.d/*weave* >/dev/null 2>&1
}

function flannel_antrea_conflict() {
    ls /etc/cni/net.d/*antrea* >/dev/null 2>&1
}

function weave_to_flannel() {
    local dst="$DIR/kustomize/flannel"
    local MGR_COUNT=""
    local MON_COUNT=""
    local OSD_COUNT=""

    # If we have Rook installed we need to scale down it before migrate
    # Otherwise, it might end up blocking the Pods termination in the
    # kube-system and if we or users force the deletion in some scenarios
    # it might end up in an unresponsive cluster with the nodes status
    # notReady. At the end we will scale up Rook again with the same
    # cephCluster values obtained found before we scale it down.
    if kubectl get namespace/rook-ceph ; then
        logStep "Scaling down Rook Ceph for the migration from Weave to Flannel"

        echo "Scaling down Rook Operator"
        kubectl -n rook-ceph scale deployment rook-ceph-operator --replicas=0
        echo "Scaling down Rook Ceph"

        # Retrieve the existing count values
        MGR_COUNT=$(kubectl -n rook-ceph get cephcluster rook-ceph -o jsonpath='{.spec.mgr.count}')
        MON_COUNT=$(kubectl -n rook-ceph get cephcluster rook-ceph -o jsonpath='{.spec.mon.count}')
        OSD_COUNT=$(kubectl -n rook-ceph get cephcluster rook-ceph -o jsonpath='{.spec.osd.count}')

        kubectl -n rook-ceph patch cephcluster rook-ceph --type merge -p '{"spec":{"mgr":{"count":0},"mon":{"count":0},"osd":{"count":0}}}'
        logSuccess "Rook Ceph is scaled down"
    fi

    logStep "Removing Weave to install Flannel"
    remove_weave

    logStep "Updating kubeadm to use Flannel"
    flannel_kubeadm

    logStep "Applying Flannel"
    kubectl -n kube-flannel apply -k "$dst/"

    # if there is more than one node, prompt to run on each primary/master node, and then on each worker/secondary node
    local master_node_count=
    master_node_count=$(kubectl get nodes --no-headers --selector='node-role.kubernetes.io/control-plane' | wc -l)
    local master_node_names=
    master_node_names=$(kubectl get nodes --no-headers --selector='node-role.kubernetes.io/control-plane' -o custom-columns=NAME:.metadata.name)
    if [ "$master_node_count" -gt 1 ]; then
        local other_master_nodes=
        other_master_nodes=$(echo "$master_node_names" | grep -v "$(get_local_node_name)")
        printf "${YELLOW}Moving primary nodes from Weave to Flannel requires removing certain weave files and restarting kubelet.${NC}\n"
        printf "${YELLOW}Please run the following command on each of the listed primary nodes:${NC}\n\n"
        printf "${other_master_nodes}\n"

        # generate the cert key once, as the hash changes each time upload-certs is called
        kubeadm init phase upload-certs --upload-certs 2>/dev/null > /tmp/kotsadm-cert-key
        local cert_key=
        cert_key=$(cat /tmp/kotsadm-cert-key | grep -v 'upload-certs' )
        rm /tmp/kotsadm-cert-key

        if [ "$AIRGAP" = "1" ]; then
            printf "\n\t${GREEN}cat ./tasks.sh | sudo bash -s weave-to-flannel-primary airgap cert-key=${cert_key}${NC}\n\n"
        else
            local prefix=
            prefix="$(build_installer_prefix "${INSTALLER_ID}" "${KURL_VERSION}" "${KURL_URL}" "${PROXY_ADDRESS}" "${PROXY_HTTPS_ADDRESS}")"
            printf "\n\t${GREEN}${prefix}tasks.sh | sudo bash -s weave-to-flannel-primary cert-key=${cert_key}${NC}\n\n"
        fi

        printf "${YELLOW}Once this has been run on all nodes, press enter to continue.${NC}"
        prompt
        kubectl -n kube-flannel delete pods --all
    fi

    local worker_node_count=
    worker_node_count=$(kubectl get nodes --no-headers --selector='!node-role.kubernetes.io/control-plane' | wc -l)
    local worker_node_names=
    worker_node_names=$(kubectl get nodes --no-headers --selector='!node-role.kubernetes.io/control-plane' -o custom-columns=NAME:.metadata.name)
    if [ "$worker_node_count" -gt 0 ]; then
        printf "${YELLOW}Moving from Weave to Flannel requires removing certain weave files and restarting kubelet.${NC}\n"
        printf "${YELLOW}Please run the following command on each of the listed secondary nodes:${NC}\n\n"
        printf "${worker_node_names}\n"

        if [ "$AIRGAP" = "1" ]; then
            printf "\n\t${GREEN}cat ./tasks.sh | sudo bash -s weave-to-flannel-secondary${NC}\n\n"
        else
            local prefix=
            prefix="$(build_installer_prefix "${INSTALLER_ID}" "${KURL_VERSION}" "${KURL_URL}" "${PROXY_ADDRESS}" "${PROXY_HTTPS_ADDRESS}")"
            printf "\n\t${GREEN}${prefix}tasks.sh | sudo bash -s weave-to-flannel-secondary airgap${NC}\n\n"
        fi

        printf "${YELLOW}Once this has been run on all nodes, press enter to continue.${NC}"
        prompt
        kubectl -n kube-flannel delete pods --all
    fi

    echo "waiting for kube-flannel-ds to become healthy in kube-flannel"
    spinner_until 240 daemonset_fully_updated "kube-flannel" "kube-flannel-ds"

    logStep "Restarting kubelet"
    systemctl stop kubelet
    iptables -t nat -F && iptables -t mangle -F && iptables -F && iptables -X
    echo "waiting for containerd to restart"
    restart_systemd_and_wait containerd
    echo "waiting for kubelet to restart"
    restart_systemd_and_wait kubelet

    logStep "Restarting pods in kube-system"
    kubectl -n kube-system delete pods --all
    kubectl -n kube-flannel delete pods --all
    flannel_ready_spinner

    logStep "Restarting CSI pods"
    kubectl -n longhorn-system delete pods --all || true
    kubectl -n rook-ceph delete pods --all || true
    kubectl -n openebs delete pods --all || true

    sleep 60
    logStep "Restarting all other pods"
    echo "this may take several minutes"
    local ns=
    for ns in $(kubectl get ns -o name | grep -Ev '(kube-system|longhorn-system|rook-ceph|openebs|kube-flannel)' | cut -f2 -d'/'); do
        kubectl delete pods -n "$ns" --all
    done

    sleep 60

    if kubectl get namespace/rook-ceph ; then
        logStep "Scaling up Rook Ceph after the migration from Weave to Flannel"

        kubectl -n rook-ceph scale deployment rook-ceph-operator --replicas=1
        logSuccess "Rook Ceph is scale up"

        PATCH='{"spec":{'

        # Check if the variable MGR_COUNT exists
        if [ -n "${MGR_COUNT}" ]; then
            PATCH+='"mgr":{"count":'"$MGR_COUNT"'}'
        fi

        if [ -n "${MON_COUNT}" ]; then
            if [[ $PATCH != '{"spec":{' ]]; then
               PATCH+=','
            fi
            PATCH+='"mon":{"count":'"$MON_COUNT"'}'
        fi

        if [ -n "${OSD_COUNT}" ]; then
            if [[ $PATCH != '{"spec":{' ]]; then
                PATCH+=','
            fi
            PATCH+='"osd":{"count":'"$OSD_COUNT"'}'
        fi

        PATCH+='}}'
        kubectl -n rook-ceph patch cephcluster rook-ceph --type merge -p $PATCH

        echo "Awaiting Ceph healthy"
        if ! "$DIR"/bin/kurl rook wait-for-health 1200 ; then
            kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
            logWarn "RookCeph is not healthy. Migration from Weave to Flannel does not seems to be completed successfully"
            return
        fi
    fi

    logSuccess "Migrated from Weave to Flannel"
}

function remove_weave() {
    local resources=("daemonset.apps/weave-net"
                     "rolebinding.rbac.authorization.k8s.io/weave-net"
                     "role.rbac.authorization.k8s.io/weave-net"
                     "clusterrolebinding.rbac.authorization.k8s.io/weave-net"
                     "clusterrole.rbac.authorization.k8s.io/weave-net"
                     "serviceaccount/weave-net"
                     "secret/weave-passwd")

    # Check if resource exists before deleting it
    for resource in "${resources[@]}"; do
        if kubectl -n kube-system get "$resource" &> /dev/null; then
            if ! timeout 60 kubectl -n kube-system delete "$resource" --ignore-not-found &> /dev/null; then
                logWarn "Timeout occurred while deleting weave resources"
            fi
        fi
    done

    if ! timeout 60 kubectl delete pods -n kube-system -l name=weave-net --ignore-not-found &> /dev/null; then
        logWarn "Timeout occurred while deleting weave Pods. Attempting force deletion."
        if ! timeout 60 kubectl delete pods -n kube-system -l name=weave-net --force --grace-period=0 1>/dev/null; then
             logWarn "Timeout occurred while force Weave Pods deletion"
        fi
    fi

    # Delete the weave network interface, if it exists
    if ip link show weave > /dev/null 2>&1; then
        ip link delete weave
    fi

    rm -rf /var/lib/weave
    rm -rf /etc/cni/net.d/*weave*
    rm -rf /opt/cni/bin/weave*

    logStep "Verifying Weave removal"

    for resource in "${resources[@]}"; do
        if kubectl -n kube-system get "$resource" &> /dev/null; then
            logWarn "Resource: $resource still exists. Attempting force deletion."
            if ! timeout 30 kubectl -n kube-system delete "$resource" --force --grace-period=0 1>/dev/null; then
                logWarn "Timeout occurred while force deleting resource: $resource"
            fi
            echo "waiting 30 seconds to check removal"
            sleep 30
        fi
    done

    for resource in "${resources[@]}"; do
        if kubectl -n kube-system get "$resource" &> /dev/null; then
            logWarn "Unable to remove resource: $resource"
            return
        fi
    done

    if kubectl get pods -n kube-system -l name=weave-net &> /dev/null; then
       logWarn "Unable to remove Weave Pods"
       return
    fi

    logSuccess "Weave has been successfully removed."
}

function flannel_kubeadm() {
    # search for 'serviceSubnet', add podSubnet above it
    local pod_cidr_range_line=
    pod_cidr_range_line="  podSubnet: ${POD_CIDR}"
    if grep -q 'podSubnet:' "$KUBEADM_CONF_FILE" ; then
        sed -i "s_  podSubnet:.*_${pod_cidr_range_line}_" "$KUBEADM_CONF_FILE"
    else
        sed -i "/serviceSubnet/ s/.*/${pod_cidr_range_line}\n&/" "$KUBEADM_CONF_FILE"
    fi

    kubeadm init phase upload-config kubeadm --config="$KUBEADM_CONF_FILE"
    kubeadm init phase control-plane controller-manager --config="$KUBEADM_CONF_FILE"
}

function flannel_already_applied() {
    # We will remove the flannel pods to let it be re-created
    # in order to workaround the issue scenario described in
    # https://github.com/flannel-io/flannel/issues/1721
    if [ "$KUBERNETES_UPGRADE" == "1" ]; then
       log "Restarting kube-flannel pods"
       kubectl rollout restart --namespace=kube-flannel daemonset/kube-flannel-ds
    fi

    flannel_ready_spinner
    check_network
}
