#!/bin/bash

export POD_CIDR
export POD_CIDR_RANGE
export POD_CIDR_IPV6
export EXISTING_POD_CIDR

export FLANNEL_ENABLE_IPV4=true
export FLANNEL_ENABLE_IPV6=false # TODO: support ipv6
export FLANNEL_BACKEND=vxlan # TODO: support encryption

function flannel_pre_init() {
    local src="$DIR/addons/flannel/$FLANNEL_VERSION"
    local dst="$DIR/kustomize/flannel"

    if flannel_weave_conflict ; then
        if [ -n "$DOCKER_VERSION" ]; then
            bail "Migrations from Weave to Flannel are only supported with containerd"
        fi
    fi

    if flannel_antrea_conflict ; then
        bail "Migrations from Antrea to Flannel are not supported"
    fi

    flannel_init_pod_subnet
}

function flannel() {
    local src="$DIR/addons/flannel/$FLANNEL_VERSION"
    local dst="$DIR/kustomize/flannel"

    cp "$src"/yaml/* "$dst/"

    flannel_render_config

    if flannel_weave_conflict; then
        printf "${YELLOW}Would you like to migrate from Weave to Flannel?${NC}"
        printf "${YELLOW}This will require whole-cluster downtime during the transition process.${NC}"
        if ! confirmY ; then
            bail "Not migrating from Weave to Flannel"
        fi

        weave_to_flannel
    else
        kubectl -n kube-flannel apply -k "$dst/"
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
    echo "waiting for Flannel to become healthy"
    if ! spinner_until 180 flannel_health_check; then
        kubectl logs -n kube-flannel -l app=flannel --all-containers --tail 10
        bail "The Flannel add-on failed to deploy successfully."
    fi
}

function flannel_weave_conflict() {
    ls /etc/cni/net.d/*weave* >/dev/null 2>&1
}

function flannel_antrea_conflict() {
    ls /etc/cni/net.d/*antrea* >/dev/null 2>&1
}

function flannel_is_single_master() {
    local nodecount=
    nodecount=$(kubectl get nodes --no-headers --selector='node-role.kubernetes.io/control-plane' | wc -l)
    if [ "$nodecount" -eq 1 ]; then
        return 0
    else
        return 1
    fi
}

function weave_to_flannel() {
    local dst="$DIR/kustomize/flannel"

    logStep "Removing Weave to install Flannel"
    remove_weave

    logStep "Updating kubeadm to use Flannel"
    flannel_kubeadm

    logStep "Applying Flannel"
    kubectl -n kube-flannel apply -k "$dst/"

    # if there is more than one node, prompt to run on each primary/master node, and then on each worker/secondary node
    local master_node_count=
    master_node_count=$(kubectl get nodes --no-headers --selector='node-role.kubernetes.io/control-plane' | wc -l)
    local hostnamevar
    hostnamevar=$(hostname)
    local master_node_names=
    master_node_names=$(kubectl get nodes --no-headers --selector='node-role.kubernetes.io/control-plane' -o custom-columns=NAME:.metadata.name | grep -v "$hostnamevar")
    if [ "$master_node_count" -gt 0 ]; then
        printf "${YELLOW}Moving primary nodes from Weave to Flannel requires removing certain weave files and restarting kubelet.${NC}\n"
        printf "${YELLOW}Please run the following command on each of the listed primary nodes:${NC}\n\n"
        printf "${master_node_names}\n"

        # generate the cert key once, as the hash changes each time
        kubeadm init phase upload-certs --upload-certs 2>/dev/null > /tmp/kotsadm-cert-key
        local cert_key=
        cert_key=$(cat /tmp/kotsadm-cert-key | grep -v 'upload-certs' )
        rm /tmp/kotsadm-cert-key

        if [ "$AIRGAP" = "1" ]; then
            printf "\n\t${GREEN}cat ./tasks.sh | sudo bash -s weave-to-flannel-primary cert-key=${cert_key}${NC}\n\n"
        else
            local prefix=
            prefix="$(build_installer_prefix "${INSTALLER_ID}" "${KURL_VERSION}" "${KURL_URL}" "${PROXY_ADDRESS}")"
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
        printf "${YELLOW}Please run the following command on each of the listed secondary nodes:${NC}\n"
        printf "${worker_node_names}\n"

        if [ "$AIRGAP" = "1" ]; then
            printf "\n\t${GREEN}cat ./tasks.sh | sudo bash -s weave-to-flannel-secondary${NC}\n\n"
        else
            local prefix=
            prefix="$(build_installer_prefix "${INSTALLER_ID}" "${KURL_VERSION}" "${KURL_URL}" "${PROXY_ADDRESS}")"
            printf "\n\t${GREEN}${prefix}tasks.sh | sudo bash -s weave-to-flannel-secondary${NC}\n\n"
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
    local ns=
    for ns in $(kubectl get ns -o name | grep -Ev '(kube-system|longhorn-system|rook-ceph|openebs|kube-flannel)' | cut -f2 -d'/'); do
        kubectl delete pods -n "$ns" --all
    done

    sleep 60
    logSuccess "Migrated from Weave to Flannel"
}

function remove_weave() {
    # firstnode only
    kubectl -n kube-system delete daemonset weave-net
    kubectl -n kube-system delete rolebinding weave-net
    kubectl -n kube-system delete role weave-net
    kubectl delete clusterrolebinding weave-net
    kubectl delete clusterrole weave-net
    kubectl -n kube-system delete serviceaccount weave-net
    kubectl -n kube-system delete secret weave-passwd

    # all nodes
    rm -f /opt/cni/bin/weave-*
    rm -rf /etc/cni/net.d
    ip link delete weave

}

function flannel_kubeadm() {
    # search for 'serviceSubnet', add podSubnet above it
    local pod_cidr_range_line=
    pod_cidr_range_line="  podSubnet: ${POD_CIDR}"
    if grep 'podSubnet:' /opt/replicated/kubeadm.conf; then
        sed -i "s_  podSubnet:.*_${pod_cidr_range_line}_" /opt/replicated/kubeadm.conf
    else
        sed -i "/serviceSubnet/ s/.*/${pod_cidr_range_line}\n&/" /opt/replicated/kubeadm.conf
    fi

    kubeadm init phase upload-config kubeadm --config=/opt/replicated/kubeadm.conf
    kubeadm init phase control-plane controller-manager --config=/opt/replicated/kubeadm.conf
}
