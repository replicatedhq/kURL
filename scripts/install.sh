#!/bin/bash

set -e
set -E # cause 'trap funcname ERR' to be inherited by child commands, see https://stackoverflow.com/questions/35800082/how-to-trap-err-when-using-set-e-in-bash

MASTER=1
DIR=.

# Magic begin: scripts are inlined for distribution. See "make build/install.sh"
. $DIR/scripts/Manifest
. $DIR/scripts/common/kurl.sh
. $DIR/scripts/common/addon.sh
. $DIR/scripts/common/common.sh
. $DIR/scripts/common/discover.sh
. $DIR/scripts/common/docker.sh
. $DIR/scripts/common/helm.sh
. $DIR/scripts/common/host-packages.sh
. $DIR/scripts/common/kubernetes.sh
. $DIR/scripts/common/object_store.sh
. $DIR/scripts/common/plugins.sh
. $DIR/scripts/common/preflights.sh
. $DIR/scripts/common/prompts.sh
. $DIR/scripts/common/proxy.sh
. $DIR/scripts/common/reporting.sh
. $DIR/scripts/common/rook.sh
. $DIR/scripts/common/rook-upgrade.sh
. $DIR/scripts/common/longhorn.sh
. $DIR/scripts/common/upgrade.sh
. $DIR/scripts/common/utilbinaries.sh
. $DIR/scripts/common/yaml.sh
. $DIR/scripts/distro/interface.sh
. $DIR/scripts/distro/kubeadm/distro.sh
. $DIR/scripts/common/containerd.sh
# Magic end

KUBERNETES_INIT_IGNORE_PREFLIGHT_ERRORS="${KUBERNETES_INIT_IGNORE_PREFLIGHT_ERRORS:-}"

function init() {
    logStep "Initialize Kubernetes"

    kubernetes_maybe_generate_bootstrap_token

    local addr="$PRIVATE_ADDRESS"
    local port="6443"
    API_SERVICE_ADDRESS="$PRIVATE_ADDRESS:6443"
    if [ "$HA_CLUSTER" = "1" ]; then
        addr="$LOAD_BALANCER_ADDRESS"
        port="$LOAD_BALANCER_PORT"
    fi
    addr=$($DIR/bin/kurl netutil format-ip-address "$addr")
    API_SERVICE_ADDRESS="$addr:$port"

    local oldLoadBalancerAddress=$(kubernetes_load_balancer_address)
    if commandExists ekco_handle_load_balancer_address_change_pre_init; then
        ekco_handle_load_balancer_address_change_pre_init $oldLoadBalancerAddress $LOAD_BALANCER_ADDRESS
    fi
    if [ "$EKCO_ENABLE_INTERNAL_LOAD_BALANCER" = "1" ] && commandExists ekco_bootstrap_internal_lb; then
        ekco_bootstrap_internal_lb
    fi

    local kustomize_kubeadm_init="$DIR/kustomize/kubeadm/init"

    local NODE_HOSTNAME=
    NODE_HOSTNAME=$(get_local_node_name)
    # if the hostname is overridden, patch the kubeadm config to use the overridden hostname
    if [ "$NODE_HOSTNAME" != "$(hostname | tr '[:upper:]' '[:lower:]')" ]; then
        render_yaml_file_2 "$kustomize_kubeadm_init/kubeadm-init-hostname.patch.tmpl.yaml" \
            > "$kustomize_kubeadm_init/kubeadm-init-hostname.patch.yaml"
        insert_patches_strategic_merge \
            $kustomize_kubeadm_init/kustomization.yaml \
            kubeadm-init-hostname.patch.yaml
    fi

    CERT_KEY=
    CERT_KEY_EXPIRY=
    if [ "$HA_CLUSTER" = "1" ]; then
        CERT_KEY=$(< /dev/urandom tr -dc a-f0-9 | head -c64)
        CERT_KEY_EXPIRY=$(TZ="UTC" date -d "+2 hour" --rfc-3339=second | sed 's/ /T/')
        insert_patches_strategic_merge \
            $kustomize_kubeadm_init/kustomization.yaml \
            patch-certificate-key.yaml
    fi

    # kustomize can merge multiple list patches in some cases but it is not working for me on the
    # ClusterConfiguration.apiServer.certSANs list
    if [ -n "$PUBLIC_ADDRESS" ] && [ -n "$LOAD_BALANCER_ADDRESS" ]; then
        insert_patches_strategic_merge \
            $kustomize_kubeadm_init/kustomization.yaml \
            patch-public-and-load-balancer-address.yaml
    elif [ -n "$PUBLIC_ADDRESS" ]; then
        insert_patches_strategic_merge \
            $kustomize_kubeadm_init/kustomization.yaml \
            patch-public-address.yaml
    elif [ -n "$LOAD_BALANCER_ADDRESS" ]; then
        insert_patches_strategic_merge \
            $kustomize_kubeadm_init/kustomization.yaml \
            patch-load-balancer-address.yaml
    fi

    # conditional kubelet configuration fields
    if [ "$KUBERNETES_TARGET_VERSION_MINOR" -ge "21" ]; then
        insert_patches_strategic_merge \
            $kustomize_kubeadm_init/kustomization.yaml \
            patch-kubelet-21.yaml
    else
        insert_patches_strategic_merge \
            $kustomize_kubeadm_init/kustomization.yaml \
            patch-kubelet-pre21.yaml
    fi
    if [ "$KUBERNETES_CIS_COMPLIANCE" == "1" ]; then
        insert_patches_strategic_merge \
            $kustomize_kubeadm_init/kustomization.yaml \
            patch-kubelet-cis-compliance.yaml
        
        if [ "$KUBERNETES_TARGET_VERSION_MINOR" -ge "20" ]; then
            insert_patches_strategic_merge \
                $kustomize_kubeadm_init/kustomization.yaml \
                patch-cluster-config-cis-compliance.yaml
	    else
            insert_patches_strategic_merge \
                $kustomize_kubeadm_init/kustomization.yaml \
                patch-cluster-config-cis-compliance-insecure-port.yaml
	    fi
    fi

    if [ "$KUBE_RESERVED" == "1" ]; then
        # gets the memory and CPU capacity of the worker node
        MEMORY_MI=$(free -m | grep Mem | awk '{print $2}')
        CPU_MILLICORES=$(($(nproc) * 1000))
        # calculates the amount of each resource to reserve
        mebibytes_to_reserve=$(get_memory_mebibytes_to_reserve $MEMORY_MI)
        cpu_millicores_to_reserve=$(get_cpu_millicores_to_reserve $CPU_MILLICORES)

        insert_patches_strategic_merge \
            $kustomize_kubeadm_init/kustomization.yaml \
            patch-kubelet-reserve-compute-resources.yaml

        render_yaml_file $kustomize_kubeadm_init/patch-kubelet-reserve-compute-resources.tpl > $kustomize_kubeadm_init/patch-kubelet-reserve-compute-resources.yaml
    fi
    if [ -n "$EVICTION_THRESHOLD" ]; then
        insert_patches_strategic_merge \
            $kustomize_kubeadm_init/kustomization.yaml \
            patch-kubelet-eviction-threshold.yaml

        render_yaml_file $kustomize_kubeadm_init/patch-kubelet-eviction-threshold.tpl > $kustomize_kubeadm_init/patch-kubelet-eviction-threshold.yaml
    fi
    if [ -n "$SYSTEM_RESERVED" ]; then
        insert_patches_strategic_merge \
            $kustomize_kubeadm_init/kustomization.yaml \
            patch-kubelet-system-reserved.yaml

        render_yaml_file $kustomize_kubeadm_init/patch-kubelet-system-reserved.tpl > $kustomize_kubeadm_init/patch-kubelet-system-reserved.yaml
    fi

    if [ -n "$CONTAINER_LOG_MAX_SIZE" ]; then
        insert_patches_strategic_merge \
            $kustomize_kubeadm_init/kustomization.yaml \
            patch-kubelet-container-log-max-size.yaml

        render_yaml_file $kustomize_kubeadm_init/patch-kubelet-container-log-max-size.tpl > $kustomize_kubeadm_init/patch-kubelet-container-log-max-size.yaml
    fi
    if [ -n "$CONTAINER_LOG_MAX_FILES" ]; then
        insert_patches_strategic_merge \
            $kustomize_kubeadm_init/kustomization.yaml \
            patch-kubelet-container-log-max-files.yaml

        render_yaml_file $kustomize_kubeadm_init/patch-kubelet-container-log-max-files.tpl > $kustomize_kubeadm_init/patch-kubelet-container-log-max-files.yaml
    fi
    if [ -n "$KUBERNETES_MAX_PODS_PER_NODE" ]; then
        insert_patches_strategic_merge \
            $kustomize_kubeadm_init/kustomization.yaml \
            patch-kubelet-max-pods.yaml

        render_yaml_file_2 $kustomize_kubeadm_init/patch-kubelet-max-pods.tmpl.yaml > $kustomize_kubeadm_init/patch-kubelet-max-pods.yaml
    fi

    kubernetes_configure_pause_image "$kustomize_kubeadm_init"

    # Add kubeadm init patches from addons.
    for patch in $(ls -1 ${kustomize_kubeadm_init}-patches/* 2>/dev/null || echo); do
        patch_basename="$(basename $patch)"
        cp "$patch" "$kustomize_kubeadm_init/$patch_basename"
        
        kubeadm_customize_config "$kustomize_kubeadm_init/$patch_basename"
        insert_patches_strategic_merge \
            $kustomize_kubeadm_init/kustomization.yaml \
            "$patch_basename"
    done
    mkdir -p "$KUBEADM_CONF_DIR"

    # Generate kubeadm config
    kubectl kustomize $kustomize_kubeadm_init > "$KUBEADM_CONF_DIR/kubeadm-init-raw.yaml"
    render_yaml_file "$KUBEADM_CONF_DIR/kubeadm-init-raw.yaml" > "$KUBEADM_CONF_FILE"

    # kustomize requires assests have a metadata field while kubeadm config will reject yaml containing it
    # this uses a go binary found in kurl/cmd/yamlutil to strip the metadata field from the yaml
    #
    cp $KUBEADM_CONF_FILE $KUBEADM_CONF_DIR/kubeadm_conf_copy_in
    $DIR/bin/yamlutil -r -fp $KUBEADM_CONF_DIR/kubeadm_conf_copy_in -yp metadata
    mv $KUBEADM_CONF_DIR/kubeadm_conf_copy_in $KUBEADM_CONF_FILE

    # When no_proxy changes kubeadm init rewrites the static manifests and fails because the api is
    # restarting. Trigger the restart ahead of time and wait for it to be healthy.
    if [ -f "/etc/kubernetes/manifests/kube-apiserver.yaml" ] && [ -n "$no_proxy" ] && ! grep -Fq "$no_proxy" /etc/kubernetes/manifests/kube-apiserver.yaml ; then
        kubeadm init phase control-plane apiserver --config $KUBEADM_CONF_FILE
        sleep 2
        if ! spinner_until 60 kubernetes_api_is_healthy; then
            echo "Failed to wait for kubernetes API restart after no_proxy change" # continue
        fi
    fi

    if [ "$HA_CLUSTER" = "1" ]; then
        UPLOAD_CERTS="--upload-certs"
    fi

    # kubeadm init temporarily taints this node which causes rook to move any mons on it and may
    # lead to a loss of quorum
    disable_rook_ceph_operator

    # since K8s 1.19.1 kubeconfigs point to local API server even in HA setup. When upgrading from
    # earlier versions and using a load balancer, kubeadm init will bail because the kubeconfigs
    # already exist pointing to the load balancer
    rm -rf /etc/kubernetes/*.conf

    # Regenerate api server cert in case load balancer address changed
    if [ -f /etc/kubernetes/pki/apiserver.crt ]; then
        mv -f /etc/kubernetes/pki/apiserver.crt /tmp/
    fi
    if [ -f /etc/kubernetes/pki/apiserver.key ]; then
        mv -f /etc/kubernetes/pki/apiserver.key /tmp/
    fi

    # ensure that /etc/kubernetes/audit.yaml exists
    cp $kustomize_kubeadm_init/audit.yaml /etc/kubernetes/audit.yaml
    mkdir -p /var/log/apiserver

    if [ -z "$KUBERNETES_INIT_IGNORE_PREFLIGHT_ERRORS" ]; then
        KUBERNETES_INIT_IGNORE_PREFLIGHT_ERRORS=all
    fi

    set -o pipefail
    cmd_retry 3 kubeadm init \
        --ignore-preflight-errors="$KUBERNETES_INIT_IGNORE_PREFLIGHT_ERRORS" \
        --config $KUBEADM_CONF_FILE \
        $UPLOAD_CERTS \
        | tee /tmp/kubeadm-init
    set +o pipefail

    # Node would be cordoned if migrated from docker to containerd
    kubectl uncordon "$(get_local_node_name)"

    if [ -n "$LOAD_BALANCER_ADDRESS" ]; then
        addr=$($DIR/bin/kurl netutil format-ip-address "$PRIVATE_ADDRESS")
        spinner_until 120 cert_has_san "$addr:6443" "$LOAD_BALANCER_ADDRESS"
    fi

    if commandExists ekco_cleanup_bootstrap_internal_lb; then
        ekco_cleanup_bootstrap_internal_lb
    fi

    spinner_kubernetes_api_stable

    exportKubeconfig
    KUBEADM_TOKEN_CA_HASH=$(cat /tmp/kubeadm-init | grep 'discovery-token-ca-cert-hash' | awk '{ print $2 }' | head -1)

    if [ "$KUBERNETES_CIS_COMPLIANCE" == "1" ]; then
        if [ "$KUBERNETES_TARGET_VERSION_MINOR" -le "24" ]; then
            kubectl apply -f $kustomize_kubeadm_init/pod-security-policy-privileged.yaml
            # patch 'PodSecurityPolicy' to kube-apiserver and wait for kube-apiserver to reconcile
            old_admission_plugins='--enable-admission-plugins=NodeRestriction'
            new_admission_plugins='--enable-admission-plugins=NodeRestriction,PodSecurityPolicy'
            sed -i "s%$old_admission_plugins%$new_admission_plugins%g"  /etc/kubernetes/manifests/kube-apiserver.yaml
            spinner_kubernetes_api_stable
        fi

        # create an 'etcd' user and group and ensure that it owns the etcd data directory (we don't care what userid these have, as etcd will still run as root)
        useradd etcd || true
        groupadd etcd || true
        chown -R etcd:etcd /var/lib/etcd
    fi

    wait_for_nodes

    # workaround as some code relies on this legacy label
    kubectl label --overwrite node "$(get_local_node_name)" node-role.kubernetes.io/master=

    enable_rook_ceph_operator

    DID_INIT_KUBERNETES=1
    logSuccess "Kubernetes Master Initialized"

    local currentLoadBalancerAddress=$(kubernetes_load_balancer_address)
    if [ "$currentLoadBalancerAddress" != "$oldLoadBalancerAddress" ]; then
        # restart scheduler and controller-manager on this node so they use the new address
        mv /etc/kubernetes/manifests/kube-scheduler.yaml /tmp/ && sleep 1 && mv /tmp/kube-scheduler.yaml /etc/kubernetes/manifests/
        mv /etc/kubernetes/manifests/kube-controller-manager.yaml /tmp/ && sleep 1 && mv /tmp/kube-controller-manager.yaml /etc/kubernetes/manifests/

        if kubernetes_has_remotes; then
            if commandExists ekco_handle_load_balancer_address_change_kubeconfigs; then
                ekco_handle_load_balancer_address_change_kubeconfigs
            fi

            if commandExists ekco_handle_load_balancer_address_change_post_init; then
                ekco_handle_load_balancer_address_change_post_init $oldLoadBalancerAddress $LOAD_BALANCER_ADDRESS
            fi
        fi

        # restart kube-proxies so they use the new address
        kubectl -n kube-system delete pods --selector=k8s-app=kube-proxy
    fi

    labelNodes
    kubectl cluster-info

    #approve csrs on the masters if cis compliance is enabled
    if [ "$KUBERNETES_CIS_COMPLIANCE" == "1" ]; then
        kubectl get csr | grep 'Pending' | grep 'kubelet-serving' | awk '{ print $1 }' | xargs -I {} kubectl certificate approve {}
    fi

    # create kurl namespace if it doesn't exist
    kubectl get ns kurl >/dev/null 2>&1 || kubectl create ns kurl --save-config

    spinner_until 120 kubernetes_default_service_account_exists
    spinner_until 120 kubernetes_service_exists

    logSuccess "Cluster Initialized"

    kubernetes_configure_coredns

    if commandExists registry_init; then
        registry_init
        
        if [ -n "$CONTAINERD_VERSION" ]; then
            ${K8S_DISTRO}_registry_containerd_configure "${DOCKER_REGISTRY_IP}"
            ${K8S_DISTRO}_containerd_restart
            spinner_kubernetes_api_healthy
        fi
    fi

    # install the kurl in-cluster troubleshoot supportbundle spec
    kubectl -n kurl apply -f "$DIR/manifests/troubleshoot.yaml"
}

function kubeadm_post_init() {
    BOOTSTRAP_TOKEN_EXPIRY=$(kubeadm token list | grep $BOOTSTRAP_TOKEN | awk '{print $3}')
    kurl_config
}

function kubernetes_maybe_generate_bootstrap_token() {
    if [ -z "$BOOTSTRAP_TOKEN" ]; then
        logStep "generate kubernetes bootstrap token"
        BOOTSTRAP_TOKEN=$(kubeadm token generate)
    fi
    echo "Kubernetes bootstrap token: ${BOOTSTRAP_TOKEN}"
    echo "This token will expire in 24 hours"
}

function kurl_config() {
    logStep "Persisting the kurl installer spec"
    if kubernetes_resource_exists kube-system configmap kurl-config; then
        kubectl -n kube-system delete configmap kurl-config
    fi

    kubectl -n kube-system create configmap kurl-config \
        --from-literal=kurl_url="$KURL_URL" \
        --from-literal=installer_id="$INSTALLER_ID" \
        --from-literal=ha="$HA_CLUSTER" \
        --from-literal=airgap="$AIRGAP" \
        --from-literal=ca_hash="$KUBEADM_TOKEN_CA_HASH" \
        --from-literal=docker_registry_ip="$DOCKER_REGISTRY_IP" \
        --from-literal=kubernetes_api_address="$API_SERVICE_ADDRESS" \
        --from-literal=bootstrap_token="$BOOTSTRAP_TOKEN" \
        --from-literal=bootstrap_token_expiration="$BOOTSTRAP_TOKEN_EXPIRY" \
        --from-literal=cert_key="$CERT_KEY" \
        --from-literal=upload_certs_expiration="$CERT_KEY_EXPIRY" \
        --from-literal=service_cidr="$SERVICE_CIDR" \
        --from-literal=pod_cidr="$POD_CIDR" \
        --from-literal=kurl_install_directory="$KURL_INSTALL_DIRECTORY_FLAG" \
        --from-literal=additional_no_proxy_addresses="$ADDITIONAL_NO_PROXY_ADDRESSES" \
        --from-literal=kubernetes_cis_compliance="$KUBERNETES_CIS_COMPLIANCE"

    logSuccess "Kurl installer spec was successfully persisted in the kurl configmap"
}

function outro() {
    echo
    if [ -z "$PUBLIC_ADDRESS" ]; then
      if [ -z "$PRIVATE_ADDRESS" ]; then
        PUBLIC_ADDRESS="<this_server_address>"
        PRIVATE_ADDRESS="<this_server_address>"
      else
        PUBLIC_ADDRESS="$PRIVATE_ADDRESS"
      fi
    fi

    local common_flags
    common_flags="${common_flags}$(get_docker_registry_ip_flag "${DOCKER_REGISTRY_IP}")"
    service_cidr=$(kubectl -n kube-system get cm kurl-config -ojsonpath='{ .data.service_cidr }')
    pod_cidr=$(kubectl -n kube-system get cm kurl-config -ojsonpath='{ .data.pod_cidr }')

    local no_proxy_addresses=""

    [ -n "$ADDITIONAL_NO_PROXY_ADDRESSES" ] && no_proxy_addresses="$ADDITIONAL_NO_PROXY_ADDRESSES"
    [ -n "$service_cidr" ] && no_proxy_addresses="${no_proxy_addresses:+$no_proxy_addresses,}$service_cidr"
    [ -n "$pod_cidr" ] && no_proxy_addresses="${no_proxy_addresses:+$no_proxy_addresses,}$pod_cidr"
    [ -n "$no_proxy_addresses" ] && common_flags="${common_flags}$(get_additional_no_proxy_addresses_flag 1 "$no_proxy_addresses")"

    common_flags="${common_flags}$(get_kurl_install_directory_flag "${KURL_INSTALL_DIRECTORY_FLAG}")"
    common_flags="${common_flags}$(get_remotes_flags)"
    common_flags="${common_flags}$(get_ipv6_flag)"

    KUBEADM_TOKEN_CA_HASH=$(cat /tmp/kubeadm-init | grep 'discovery-token-ca-cert-hash' | awk '{ print $2 }' | head -1)

    printf "\n"
    printf "\t\t${GREEN}Installation${NC}\n"
    printf "\t\t${GREEN}  Complete ✔${NC}\n"

    addon_outro
    printf "\n"
    kubeconfig_setup_outro
    printf "\n"
    if [ "$OUTRO_NOTIFIY_TO_RESTART_DOCKER" = "1" ]; then
        printf "\n"
        printf "\n"
        printf "The local /etc/docker/daemon.json has been merged with the spec from the installer, but has not been applied. To apply restart docker."
        printf "\n"
        printf "\n"
        printf "${GREEN} systemctl daemon-reload${NC}\n"
        printf "${GREEN} systemctl restart docker${NC}\n"
        printf "\n"
        printf "These settings will automatically be applied on the next restart."
        printf "\n"
    fi
    printf "\n"
    printf "\n"

    local prefix=
    prefix="$(build_installer_prefix "${INSTALLER_ID}" "${KURL_VERSION}" "${KURL_URL}" "${PROXY_ADDRESS}" "${PROXY_HTTPS_ADDRESS}")"

    if [ "$HA_CLUSTER" = "1" ]; then
        printf "Master node join commands expire after two hours, and worker node join commands expire after 24 hours.\n"
        printf "\n"
        if [ "$AIRGAP" = "1" ]; then
            printf "To generate new node join commands, run ${GREEN}cat ./tasks.sh | sudo bash -s join_token ha airgap${NC} on an existing master node.\n"
        else 
            printf "To generate new node join commands, run ${GREEN}${prefix}tasks.sh | sudo bash -s join_token ha${NC} on an existing master node.\n"
        fi
    else
        printf "Node join commands expire after 24 hours.\n"
        printf "\n"
        if [ "$AIRGAP" = "1" ]; then
            printf "To generate new node join commands, run ${GREEN}cat ./tasks.sh | sudo bash -s join_token airgap${NC} on this node.\n"
        else 
            printf "To generate new node join commands, run ${GREEN}${prefix}tasks.sh | sudo bash -s join_token${NC} on this node.\n"
        fi
    fi

    if [ "$AIRGAP" = "1" ]; then
        printf "\n"
        printf "To add worker nodes to this installation, copy and unpack this bundle on your other nodes, and run the following:"
        printf "\n"
        printf "\n"
        printf "${GREEN}    cat ./join.sh | sudo bash -s airgap kubernetes-master-address=${API_SERVICE_ADDRESS} kubeadm-token=${BOOTSTRAP_TOKEN} kubeadm-token-ca-hash=${KUBEADM_TOKEN_CA_HASH} kubernetes-version=${KUBERNETES_VERSION} ekco-address=${EKCO_ADDRESS} ekco-auth-token=${EKCO_AUTH_TOKEN}${common_flags}\n"
        printf "${NC}"
        printf "\n"
        printf "\n"
        if [ "$HA_CLUSTER" = "1" ]; then
            printf "\n"
            printf "To add ${GREEN}MASTER${NC} nodes to this installation, copy and unpack this bundle on your other nodes, and run the following:"
            printf "\n"
            printf "\n"
            printf "${GREEN}    cat ./join.sh | sudo bash -s airgap kubernetes-master-address=${API_SERVICE_ADDRESS} kubeadm-token=${BOOTSTRAP_TOKEN} kubeadm-token-ca-hash=${KUBEADM_TOKEN_CA_HASH} kubernetes-version=${KUBERNETES_VERSION} cert-key=${CERT_KEY} control-plane ekco-address=${EKCO_ADDRESS} ekco-auth-token=${EKCO_AUTH_TOKEN}${common_flags}\n"
            printf "${NC}"
            printf "\n"
            printf "\n"
        fi
    else
        printf "\n"
        printf "To add worker nodes to this installation, run the following script on your other nodes:"
        printf "\n"
        printf "${GREEN}    ${prefix}join.sh | sudo bash -s kubernetes-master-address=${API_SERVICE_ADDRESS} kubeadm-token=${BOOTSTRAP_TOKEN} kubeadm-token-ca-hash=${KUBEADM_TOKEN_CA_HASH} kubernetes-version=${KUBERNETES_VERSION} ekco-address=${EKCO_ADDRESS} ekco-auth-token=${EKCO_AUTH_TOKEN}${common_flags}\n"
        printf "${NC}"
        printf "\n"
        printf "\n"
        if [ "$HA_CLUSTER" = "1" ]; then
            printf "\n"
            printf "To add ${GREEN}MASTER${NC} nodes to this installation, run the following script on your other nodes:"
            printf "\n"
            printf "${GREEN}    ${prefix}join.sh | sudo bash -s kubernetes-master-address=${API_SERVICE_ADDRESS} kubeadm-token=${BOOTSTRAP_TOKEN} kubeadm-token-ca-hash=$KUBEADM_TOKEN_CA_HASH kubernetes-version=${KUBERNETES_VERSION} cert-key=${CERT_KEY} control-plane ekco-address=${EKCO_ADDRESS} ekco-auth-token=${EKCO_AUTH_TOKEN}${common_flags}\n"
            printf "${NC}"
            printf "\n"
            printf "\n"
        fi
    fi
}

function all_kubernetes_install() {
    kubernetes_host
    install_helm
    ${K8S_DISTRO}_addon_for_each addon_load
    helm_load
    init
    apply_installer_crd
}

function report_kubernetes_install() {
    report_addon_start "kubernetes" "$KUBERNETES_VERSION"
    export REPORTING_CONTEXT_INFO="kubernetes $KUBERNETES_VERSION"
    all_kubernetes_install
    export REPORTING_CONTEXT_INFO=""
    report_addon_success "kubernetes" "$KUBERNETES_VERSION"
}

K8S_DISTRO=kubeadm

function main() {
    logStep "Running install with the argument(s): $*"
    require_root_user
    # ensure /usr/local/bin/kubectl-plugin is in the path
    path_add "/usr/local/bin"
    kubernetes_init_hostname
    get_patch_yaml "$@"
    maybe_read_kurl_config_from_cluster

    if [ "$AIRGAP" = "1" ]; then
        move_airgap_assets
    fi
    pushd_install_directory

    yaml_airgap
    proxy_bootstrap
    download_util_binaries
    get_machine_id
    merge_yaml_specs
    apply_bash_flag_overrides "$@"
    parse_yaml_into_bash_variables
    MASTER=1 # parse_yaml_into_bash_variables will unset master
    prompt_license

    export KUBECONFIG=/etc/kubernetes/admin.conf

    is_ha
    parse_kubernetes_target_version
    discover full-cluster
    report_install_start
    trap ctrl_c SIGINT # trap ctrl+c (SIGINT) and handle it by reporting that the user exited intentionally (along with the line/version/etc)
    trap trap_report_error ERR # trap errors and handle it by reporting the error line and parent function
    preflights
    init_preflights
    kubernetes_upgrade_preflight
    common_prompts
    journald_persistent
    configure_proxy
    configure_no_proxy_preinstall
    ${K8S_DISTRO}_addon_for_each addon_fetch
    kubernetes_get_packages
    preflights_require_host_packages
    if [ -z "$CURRENT_KUBERNETES_VERSION" ]; then
        host_preflights "1" "0" "0"
        cluster_preflights "1" "0" "0"
    else
        host_preflights "1" "0" "1"
        cluster_preflights "1" "0" "1"
    fi
    install_host_dependencies
    get_common
    setup_kubeadm_kustomize
    rook_upgrade_maybe_report_upgrade_rook
    kubernetes_pre_init
    ${K8S_DISTRO}_addon_for_each addon_pre_init
    discover_pod_subnet
    discover_service_subnet
    configure_no_proxy
    install_cri
    kubernetes_configure_pause_image_upgrade
    get_shared
    report_upgrade_kubernetes
    report_kubernetes_install
    export SUPPORT_BUNDLE_READY=1 # allow ctrl+c and ERR traps to collect support bundles now that k8s is installed
    kurl_init_config
    maybe_set_kurl_cluster_uuid
    kurl_install_support_bundle_configmap
    ${K8S_DISTRO}_addon_for_each addon_install
    maybe_cleanup_rook
    maybe_cleanup_longhorn
    helmfile_sync
    kubeadm_post_init
    uninstall_docker
    ${K8S_DISTRO}_addon_for_each addon_post_init
    check_proxy_config
    rook_maybe_migrate_from_openebs
    outro
    package_cleanup

    popd_install_directory

    report_install_success
}

# tee logs into /var/log/kurl/install-<date>.log and stdout
mkdir -p /var/log/kurl
LOGFILE="/var/log/kurl/install-$(date +"%Y-%m-%dT%H-%M-%S").log"
main "$@" 2>&1 | tee $LOGFILE
# it is required to return the exit status of the script
FINAL_RESULT="${PIPESTATUS[0]}"
sed -i "/\b\(password\)\b/d" $LOGFILE > /dev/null 2>&1
exit "$FINAL_RESULT"
