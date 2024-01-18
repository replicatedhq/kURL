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

    if ! flannel_weave_conflict; then
        return 0
    fi

    logWarn "The migration from Weave to Flannel will require whole-cluster downtime."
    logWarn "Would you like to continue?"
    if ! confirmY ; then
        bail "Not migrating from Weave to Flannel"
    fi

    # flannel_init_pod_subnet will fail to read the pod cidr when using weave
    # because weave installation does not seem to populate the pod cidr property
    # on the kubeadm cm. here we attempt to read the data directly from the
    # weave-net daemonset.
    local weave_pod_cidr
    weave_pod_cidr=$(flannel_find_weave_pod_cidr)
    if [ -z "$EXISTING_POD_CIDR" ] && [ -n "$weave_pod_cidr" ]; then
        EXISTING_POD_CIDR="$weave_pod_cidr"
    fi

    # if the migration from weave has failed before we may have a cluster with a
    # non working network, in this scenario we can't simply move forward because
    # other addons may fail during their pre_init phase. we need to jump from here
    # directly into the weave to flannel migration code. subsequent call to install
    # flannel again will be, essentially, a noop.
    if flannel_weave_migration_has_failed; then
        logWarn "Previous attempt to migrate from Weave to Flannel has failed."
        logWarn "Attempting to migrate again, do you wish to continue?"
        if ! confirmY ; then
            bail "Not migrating from Weave to Flannel"
        fi
        discover_pod_subnet
        discover_service_subnet
        flannel
        return 0
    fi

    flannel_check_nodes_connectivity
    flannel_check_rook_ceph_status
}

function flannel_check_rook_ceph_status() {
    if kubectl get namespace/rook-ceph ; then
       logStep "Checking Rook Status prior to migrating from Weave to Flannel"
       if ! "$DIR"/bin/kurl rook wait-for-health 300 ; then
           kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
           bail "Failed to verify Rook, Ceph is not healthy. The migration from Weave to Flannel can not be performed"
           bail "Please, ensure that Rook Ceph is healthy."
       fi
       logSuccess "Rook Ceph is healthy"
    fi
}

# flannel_find_weave_pod_cidr reads the weave pod cidr directly from the weave-net daemonset.
function flannel_find_weave_pod_cidr() {
    kubectl get daemonset weave-net -n kube-system -o yaml 2>/dev/null |grep "name: IPALLOC_RANGE" -A1 | tail -1 | awk '{ print $NF }'
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

    mkdir -p "$dst"
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

    if flannel_detect_vmware_nic; then
        flannel_install_ethtool_service "$src"
    fi

    flannel_ready_spinner
    check_network
}

function flannel_detect_vmware_nic() {
    local vmxnet3=false

    if lspci -v | grep Ethernet | grep -q "VMware VMXNET3"; then
        vmxnet3=true
    fi

    return $vmxnet3
}


function flannel_install_ethtool_service() {
    # this disables the tcp checksum offloading on flannel interface - this is a workaround for
    # certain VMWare NICs that use NSX and have a conflict with the way the checksum is handled by
    # the kernel.
    local src="$1"

    logStep "

    logStep "Installing flannel ethtool service"

    cp "$src/flannel-ethtool.service" /etc/systemd/system/flannel-ethtool.service

    systemctl daemon-reload
    systemctl enable flannel-ethtool.service
    if ! timeout 30s systemctl start flannel-ethtool.service; then
        log "Failed to start flannel-ethtool.service within 30s, restarting it"
        systemctl restart flannel-ethtool.service
    fi

    logSuccess "Flannel ethtool service installed"
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
    logSubstep "Waiting up to 5 minutes for Flannel to become healthy"
    if ! spinner_until 300 flannel_health_check; then
        kubectl logs -n kube-flannel -l app=flannel --all-containers --tail 10 || true
        bail "The Flannel add-on failed to deploy successfully."
    fi
    logSuccess "Flannel is healthy"
}

# flannel_weave_conflict returns true if weave is installed or a previous migration to
# flannel was failed. on these scenarios we need to run the weave-to-flannel migration.
function flannel_weave_conflict() {
    if ls /etc/cni/net.d/*weave* >/dev/null 2>&1; then
        return 0
    fi
    flannel_weave_migration_has_failed
}

# flannel_weave_migration_has_failed returns true if a previous migration to flannel
# was failed.
function flannel_weave_migration_has_failed() {
    # this config map is created when the migration from weave to flannel is started
    # and removed when it is finished. if we find this config map then we know that
    # we have failed in a previous attempt to migrate.
    kubectl get cm -n kurl migration-from-weave >/dev/null 2>&1
}

function flannel_antrea_conflict() {
    ls /etc/cni/net.d/*antrea* >/dev/null 2>&1
}

function flannel_scale_down_ekco() {
    if ! kubernetes_resource_exists kurl deployment ekc-operator ; then
        return
    fi

    if [ "$(kubectl -n kurl get deployments ekc-operator -o jsonpath='{.spec.replicas}')" = "0" ]; then
        return
    fi
    logSubstep "Scaling down Ekco Operator"
    kubectl -n kurl scale deployment ekc-operator --replicas=0

    log "Waiting for ekco pods to be removed"
    if ! spinner_until 300 ekco_pods_gone; then
        bail "Unable to scale down ekco operator"
    fi
    logSuccess "Ecko Operator is scaled down"
}

# rook_scale_up_ekco will scale up ekco to 1 replica
function flannel_scale_up_ekco() {
    if ! kubernetes_resource_exists kurl deployment ekc-operator ; then
        return
    fi

    logSubstep "Scaling up Ecko Operator"
    if ! timeout 120 kubectl -n kurl scale deployment ekc-operator --replicas=1 1>/dev/null; then
        logWarn "Failed to scale down Ecko Operator within the timeout period."
        return
    fi

    logSuccess "Ecko is scaled up"
}


# rook_scale_down_prometheus will scale down prometheus to 0 replicas
function flannel_scale_down_prometheus() {
    if ! kubernetes_resource_exists monitoring prometheus k8s ; then
        return
    fi

    if [ "$(kubectl -n monitoring get prometheus k8s -o jsonpath='{.spec.replicas}')" = "0" ]; then
        return
    fi

    logSubstep "Scaling down Prometheus"

    log "Patching prometheus to scale down"
    if ! timeout 120 kubectl -n monitoring patch prometheus k8s --type='json' --patch '[{"op": "replace", "path": "/spec/replicas", value: 0}]' 1>/dev/null; then
        logWarn "Failed to patch Prometheus to scale down within the timeout period."
    fi

    log "Waiting 30 seconds to let Prometheus scale down"
    sleep 30

    log "Waiting for prometheus pods to be removed"
    if ! spinner_until 300 prometheus_pods_gone; then
        logWarn "Prometheus pods still running. Trying once more"
        kubectl -n monitoring patch prometheus k8s --type='json' --patch '[{"op": "replace", "path": "/spec/replicas", value: 0}]'
        if ! spinner_until 300 prometheus_pods_gone; then
            bail "Unable to scale down prometheus"
        fi
    fi
    logSuccess "Prometheus is scaled down"
}

# flannel_scale_up_prometheus will scale up prometheus replicas to 2
function flannel_scale_up_prometheus() {
    if ! kubernetes_resource_exists monitoring prometheus k8s ; then
        return
    fi

    logSubstep "Scaling up Prometheus"
    if ! timeout 120 kubectl -n monitoring patch prometheus k8s --type='json' --patch '[{"op": "replace", "path": "/spec/replicas", value: 2}]' 1>/dev/null; then
        logWarn "Failed to patch Prometheus to scale up within the timeout period."
    fi

    log "Awaiting Prometheus pods to transition to Running"
    if ! spinner_until 300 check_for_running_pods "monitoring"; then
        logWarn "Prometheus scale up did not complete within the allotted time"
        return
    fi

    logSuccess "Prometheus is scaled up"
}

function flannel_scale_down_rook() {
    if ! kubernetes_resource_exists rook-ceph deployment rook-ceph-operator; then
        return
    fi

    logSubstep "Scaling down Rook Ceph for the migration from Weave to Flannel"
    log "Scaling down Rook Operator"
    if ! timeout 300 kubectl -n rook-ceph scale deployment rook-ceph-operator --replicas=0 1>/dev/null; then
        kubectl logs -n rook-ceph -l app=rook-ceph-operator --all-containers --tail 10 || true
        bail "The Rook Ceph operator failed to scale down within the timeout period."
    fi

    logSuccess "Rook Ceph is scaled down"
}

function flannel_scale_up_rook() {
    if ! kubernetes_resource_exists rook-ceph deployment rook-ceph-operator; then
        return
    fi

    logSubstep "Scaling up Rook Ceph"
    if ! timeout 120 kubectl -n rook-ceph scale deployment rook-ceph-operator --replicas=1 1>/dev/null; then
        logWarn "Failed to scale up Rook Operator within the timeout period."
    fi

    log "Waiting for Ceph to become healthy"
    if ! "$DIR"/bin/kurl rook wait-for-health 1200 ; then
        kubectl logs -n rook-ceph -l app=rook-ceph-operator --all-containers --tail 10 || true
        kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
        logWarn "Rook Ceph is not healthy. Migration from Weave to Flannel does not seems to have been completed successfully"
        return
    fi

    logSuccess "Rook Ceph scale has been restored"
}

function weave_to_flannel() {
    local dst="$DIR/kustomize/flannel"

    # start by creating a config map indicating that this migration has been started. if we fail
    # midair this ensure this function will be ran once more.
    kubectl create configmap -n kurl migration-from-weave --from-literal=started="true" --dry-run=client -o yaml | kubectl apply -f -

    logStep "Scaling down services prior to removing Weave"
    flannel_scale_down_ekco
    flannel_scale_down_rook
    flannel_scale_down_prometheus
    logSuccess "Services scaled down successfully"

    remove_weave
    flannel_kubeadm

    log "Flushing IP Tables"
    weave_flush_iptables
    log "Waiting for containerd to restart"

    logStep "Applying Flannel"
    kubectl -n kube-flannel apply -k "$dst/"
    logSuccess "Flannel applied successfully"


    # if there is more than one node, prompt to run on each primary/master node, and then on each worker/secondary node
    local master_node_count=
    master_node_count=$(kubectl get nodes --no-headers --selector='node-role.kubernetes.io/control-plane' | wc -l)
    local master_node_names=
    master_node_names=$(kubectl get nodes --no-headers --selector='node-role.kubernetes.io/control-plane' -o custom-columns=NAME:.metadata.name)
    if [ "$master_node_count" -gt 1 ]; then
        logStep "Required to remove Weave from Primary Nodes"

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
            local command=
            command=$(printf "cat ./tasks.sh | sudo bash -s weave-to-flannel-primary airgap cert-key=%s" "$cert_key")

            for nodeName in $other_master_nodes; do
                echo "$command" > "$DIR/remotes/$nodeName"
            done

            printf "\n\t${GREEN}%s${NC}\n\n" "$command"
        else
            local prefix=
            prefix="$(build_installer_prefix "${INSTALLER_ID}" "${KURL_VERSION}" "${KURL_URL}" "${PROXY_ADDRESS}" "${PROXY_HTTPS_ADDRESS}")"

            local command=
            command=$(printf "%stasks.sh | sudo bash -s weave-to-flannel-primary cert-key=%s" "$prefix" "$cert_key")

            for nodeName in $other_master_nodes; do
                echo "$command" > "$DIR/remotes/$nodeName"
            done

            printf "\n\t${GREEN}%s${NC}\n\n" "$command"
        fi

        printf "${YELLOW}Once this has been run on all nodes, press enter to continue.${NC}"
        if [ "$ASSUME_YES" = "1" ]; then
            echo ""
            echo "The 'yes' flag has been passed, so we will wait for 5 minutes here for this to run on remote nodes"
            sleep 300
        else
            prompt
        fi

        logSuccess "User confirmation about nodes execution."
        log "Deleting Pods from kube-flannel"
        kubectl -n kube-flannel delete pods --all
    fi

    local worker_node_count=
    worker_node_count=$(kubectl get nodes --no-headers --selector='!node-role.kubernetes.io/control-plane' | wc -l)
    local worker_node_names=
    worker_node_names=$(kubectl get nodes --no-headers --selector='!node-role.kubernetes.io/control-plane' -o custom-columns=NAME:.metadata.name)
    if [ "$worker_node_count" -gt 0 ]; then
        logStep "Required to remove Weave from Nodes"

        printf "${YELLOW}Moving from Weave to Flannel requires removing certain weave files and restarting kubelet.${NC}\n"
        printf "${YELLOW}Please run the following command on each of the listed secondary nodes:${NC}\n\n"
        printf "${worker_node_names}\n"

        if [ "$AIRGAP" = "1" ]; then
            local command=
            command="cat ./tasks.sh | sudo bash -s weave-to-flannel-secondary airgap"

            for nodeName in $worker_node_names; do
                echo "$command" > "$DIR/remotes/$nodeName"
            done

            printf "\n\t${GREEN}%s${NC}\n\n" "$command"
        else
            local prefix=
            prefix="$(build_installer_prefix "${INSTALLER_ID}" "${KURL_VERSION}" "${KURL_URL}" "${PROXY_ADDRESS}" "${PROXY_HTTPS_ADDRESS}")"

            local command=
            command=$(printf "%stasks.sh | sudo bash -s weave-to-flannel-secondary" "$prefix")

            for nodeName in $worker_node_names; do
                echo "$command" > "$DIR/remotes/$nodeName"
            done

            printf "\n\t${GREEN}%s${NC}\n\n" "$command"
        fi

        printf "${YELLOW}Once this has been run on all nodes, press enter to continue.${NC}"
        if [ "$ASSUME_YES" = "1" ]; then
            echo "The 'yes' flag has been passed, so we will wait for 5 minutes here for this to run on remote nodes"
            sleep 300
        else
            prompt
        fi

        kubectl -n kube-flannel delete pods --all
    fi

    log "Waiting for kube-flannel-ds to become healthy in kube-flannel"
    if ! spinner_until 240 daemonset_fully_updated "kube-flannel" "kube-flannel-ds"; then
       logWarn "Unable to fully update Kube Flannel daemonset"
    fi

    logStep "Restarting kubelet"
    log "Stopping Kubelet"
    systemctl stop kubelet
    restart_systemd_and_wait containerd
    log "Waiting for kubelet to restart"
    restart_systemd_and_wait kubelet

    logStep "Restarting pods in kube-system"
    log "it may take several minutes to delete all pods"
    kubectl -n kube-system delete pods --all

    logStep "Restarting pods in kube-flannel"
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

    logStep "Scale up services"
    flannel_scale_up_ekco
    flannel_scale_up_prometheus
    flannel_scale_up_rook
    logSuccess "Services scaled up successfully"

    # delete the configmap that was used to signalize the weave to flannel migration start.
    kubectl delete configmap -n kurl migration-from-weave
    logSuccess "Migration from Weave to Flannel finished"
}

# weave_flush_iptables removes all weave related iptables rules from the node.
# existing rules that do not refer to weave or kubernetes are preserved.
function weave_flush_iptables() {
    # save all rules that do not mention kube or weave.
    local fpath
    fpath=$(mktemp /tmp/kurl-iptables-rules-XXXX)
    iptables-save | grep -v KUBE | grep -v WEAVE > "$fpath"
    # temporarily change the INPUT chain policy so we don't loose access to the machine
    # and then hammer everything out of existence.
    iptables -P INPUT ACCEPT
    iptables -t nat -F && iptables -t mangle -F && iptables -F && iptables -X
    # restore the rules that were not removed.
    iptables-restore < "$fpath"
    rm -f "$fpath"
}

function remove_weave() {
    logStep "Removing Weave to install Flannel"
    local resources=("daemonset.apps/weave-net"
                     "rolebinding.rbac.authorization.k8s.io/weave-net"
                     "role.rbac.authorization.k8s.io/weave-net"
                     "clusterrolebinding.rbac.authorization.k8s.io/weave-net"
                     "clusterrole.rbac.authorization.k8s.io/weave-net"
                     "serviceaccount/weave-net"
                     "secret/weave-passwd")

    # Seems that we need to delete first the daemonset
    log "Remove weave resources"
    if ! timeout 60 kubectl delete daemonset.apps/weave-net -n kube-system --ignore-not-found 1>/dev/null; then
         logWarn "Timeout occurred while delete  daemonset.apps/weave-net"
    fi

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

    log "Delete the weave network interface, if it exists"
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

    if kubectl get pods -n kube-system -l name=weave-net 2>/dev/null | grep -q .; then
        logWarn "Forcing deletion of Weave Pods"
        if ! timeout 60 kubectl delete pods -n kube-system -l name=weave-net --force 1>/dev/null; then
             logWarn "Timeout occurred while force Weave Pods deletion"
        fi
        echo "waiting 30 seconds to check removal"
        sleep 30
    fi

    for resource in "${resources[@]}"; do
        if kubectl -n kube-system get "$resource" &> /dev/null; then
            bail "Unable to remove Weave resources to move with the migration"
        fi
    done

    if kubectl get pods -n kube-system -l name=weave-net 2>/dev/null | grep -q .; then
        bail "Weave pods still exist. Unable to proceed with the migration."
    fi

    logSuccess "Weave has been successfully removed."
}

function flannel_kubeadm() {
    logStep "Updating kubeadm to use Flannel"
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
    logSuccess "Kubeadm updated successfully"
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
