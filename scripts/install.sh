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
. $DIR/scripts/common/k3s.sh
. $DIR/scripts/common/kubernetes.sh
. $DIR/scripts/common/object_store.sh
. $DIR/scripts/common/plugins.sh
. $DIR/scripts/common/preflights.sh
. $DIR/scripts/common/prompts.sh
. $DIR/scripts/common/proxy.sh
. $DIR/scripts/common/reporting.sh
. $DIR/scripts/common/rook.sh
. $DIR/scripts/common/rke2.sh
. $DIR/scripts/common/upgrade.sh
. $DIR/scripts/common/utilbinaries.sh
. $DIR/scripts/common/yaml.sh
. $DIR/scripts/distro/interface.sh
. $DIR/scripts/distro/k3s/distro.sh
. $DIR/scripts/distro/kubeadm/distro.sh
. $DIR/scripts/distro/rke2/distro.sh
# Magic end

function configure_coredns() {
    # Runs after kubeadm init which always resets the coredns configmap - no need to check for
    # and revert a previously set nameserver
    if [ -z "$NAMESERVER" ]; then
        return 0
    fi
    kubectl -n kube-system get configmap coredns -oyaml > /tmp/Corefile
    # Example lines to replace from k8s 1.17 and 1.19
    # "forward . /etc/resolv.conf" => "forward . 8.8.8.8"
    # "forward . /etc/resolv.conf {" => "forward . 8.8.8.8 {"
    sed -i "s/forward \. \/etc\/resolv\.conf/forward \. ${NAMESERVER}/" /tmp/Corefile
    kubectl -n kube-system replace configmap coredns -f /tmp/Corefile
    kubectl -n kube-system rollout restart deployment/coredns
}

function init() {
    logStep "Initialize Kubernetes"

    kubernetes_maybe_generate_bootstrap_token

    API_SERVICE_ADDRESS="$PRIVATE_ADDRESS:6443"
    if [ "$HA_CLUSTER" = "1" ]; then
        API_SERVICE_ADDRESS="$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT"
    fi

    local oldLoadBalancerAddress=$(kubernetes_load_balancer_address)
    if commandExists ekco_handle_load_balancer_address_change_pre_init; then
        ekco_handle_load_balancer_address_change_pre_init $oldLoadBalancerAddress $LOAD_BALANCER_ADDRESS
    fi

    kustomize_kubeadm_init=./kustomize/kubeadm/init
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

    # Add kubeadm init patches from addons.
    for patch in $(ls -1 ${kustomize_kubeadm_init}-patches/* 2>/dev/null || echo); do
        patch_basename="$(basename $patch)"
        cp $patch $kustomize_kubeadm_init/$patch_basename
        insert_patches_strategic_merge \
            $kustomize_kubeadm_init/kustomization.yaml \
            $patch_basename
    done
    mkdir -p "$KUBEADM_CONF_DIR"
    kubectl kustomize $kustomize_kubeadm_init > $KUBEADM_CONF_DIR/kubeadm-init-raw.yaml
    render_yaml_file $KUBEADM_CONF_DIR/kubeadm-init-raw.yaml > $KUBEADM_CONF_FILE

    # kustomize requires assests have a metadata field while kubeadm config will reject yaml containing it
    # this uses a go binary found in kurl/cmd/yamlutil to strip the metadata field from the yaml
    #
    cp $KUBEADM_CONF_FILE $KUBEADM_CONF_DIR/kubeadm_conf_copy_in
    $DIR/bin/yamlutil -r -fp $KUBEADM_CONF_DIR/kubeadm_conf_copy_in -yf metadata
    mv $KUBEADM_CONF_DIR/kubeadm_conf_copy_in $KUBEADM_CONF_FILE

    if [ "$KUBERNETES_TARGET_VERSION_MINOR" -ge "21" ]; then
        cat << EOF >> $KUBEADM_CONF_FILE
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
shutdownGracePeriod: 30s
shutdownGracePeriodCriticalPods: 10s
---
EOF
    else
        cat << EOF >> $KUBEADM_CONF_FILE
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
---
EOF
    fi

    # When no_proxy changes kubeadm init rewrites the static manifests and fails because the api is
    # restarting. Trigger the restart ahead of time and wait for it to be healthy.
    if [ -f "/etc/kubernetes/manifests/kube-apiserver.yaml" ] && [ -n "$no_proxy" ] && ! cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep -q "$no_proxy"; then
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

    set -o pipefail
    kubeadm init \
        --ignore-preflight-errors=all \
        --config $KUBEADM_CONF_FILE \
        $UPLOAD_CERTS \
        | tee /tmp/kubeadm-init
    set +o pipefail

    if [ -n "$LOAD_BALANCER_ADDRESS" ]; then
        spinner_until 120 cert_has_san "$PRIVATE_ADDRESS:6443" "$LOAD_BALANCER_ADDRESS"
    fi

    spinner_kubernetes_api_stable

    exportKubeconfig
    KUBEADM_TOKEN_CA_HASH=$(cat /tmp/kubeadm-init | grep 'discovery-token-ca-cert-hash' | awk '{ print $2 }' | head -1)

    wait_for_nodes
    enable_rook_ceph_operator

    DID_INIT_KUBERNETES=1
    logSuccess "Kubernetes Master Initialized"

    local currentLoadBalancerAddress=$(kubernetes_load_balancer_address)
    if [ "$currentLoadBalancerAddress" != "$oldLoadBalancerAddress" ]; then
        # restart scheduler and controller-manager on this node so they use the new address
        mv /etc/kubernetes/manifests/kube-scheduler.yaml /tmp/ && sleep 1 && mv /tmp/kube-scheduler.yaml /etc/kubernetes/manifests/
        mv /etc/kubernetes/manifests/kube-controller-manager.yaml /tmp/ && sleep 1 && mv /tmp/kube-controller-manager.yaml /etc/kubernetes/manifests/
        # restart kube-proxies so they use the new address
        kubectl -n kube-system delete pods --selector=k8s-app=kube-proxy

        if kubernetes_has_remotes; then
            printf "${YELLOW}\nThe load balancer address has changed. Run the following on all remote nodes to use the new address${NC}\n"
            printf "\n"
            if [ "$AIRGAP" = "1" ]; then
                printf "${GREEN}    cat ./tasks.sh | sudo bash -s set-kubeconfig-server https://${currentLoadBalancerAddress}${NC}\n"
            else
                local prefix=
                prefix="$(build_installer_prefix "${INSTALLER_ID}" "${KURL_VERSION}" "${KURL_URL}" "${PROXY_ADDRESS}")"

                printf "${GREEN}    ${prefix}tasks.sh | sudo bash -s set-kubeconfig-server https://${currentLoadBalancerAddress}${NC}\n"
            fi

            printf "\n"
            printf "Continue? "
            confirmN

            if commandExists ekco_handle_load_balancer_address_change_post_init; then
                ekco_handle_load_balancer_address_change_post_init $oldLoadBalancerAddress $LOAD_BALANCER_ADDRESS
            fi
        fi
    fi

    labelNodes
    kubectl cluster-info

    # create kurl namespace if it doesn't exist
    kubectl get ns kurl 2>/dev/null 1>/dev/null || kubectl create ns kurl 1>/dev/null

    spinner_until 120 kubernetes_default_service_account_exists
    spinner_until 120 kubernetes_service_exists

    logSuccess "Cluster Initialized"

    configure_coredns

    if commandExists registry_containerd_init && [ -n "$CONTAINERD_VERSION" ] && [ "$SKIP_DOCKER_INSTALL" != "1" ]; then
        registry_containerd_init
    fi
}

function post_init() {
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
        --from-literal=kurl_install_directory="$KURL_INSTALL_DIRECTORY_FLAG"
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
    common_flags="${common_flags}$(get_additional_no_proxy_addresses_flag "${PROXY_ADDRESS}" "${SERVICE_CIDR},${POD_CIDR}")"
    common_flags="${common_flags}$(get_kurl_install_directory_flag "${KURL_INSTALL_DIRECTORY_FLAG}")"
    common_flags="${common_flags}$(get_remotes_flags)"

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
    prefix="$(build_installer_prefix "${INSTALLER_ID}" "${KURL_VERSION}" "${KURL_URL}" "${PROXY_ADDRESS}")"

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
        printf "${GREEN}    cat ./join.sh | sudo bash -s airgap kubernetes-master-address=${API_SERVICE_ADDRESS} kubeadm-token=${BOOTSTRAP_TOKEN} kubeadm-token-ca-hash=${KUBEADM_TOKEN_CA_HASH} kubernetes-version=${KUBERNETES_VERSION}${common_flags}\n"
        printf "${NC}"
        printf "\n"
        printf "\n"
        if [ "$HA_CLUSTER" = "1" ]; then
            printf "\n"
            printf "To add ${GREEN}MASTER${NC} nodes to this installation, copy and unpack this bundle on your other nodes, and run the following:"
            printf "\n"
            printf "\n"
            printf "${GREEN}    cat ./join.sh | sudo bash -s airgap kubernetes-master-address=${API_SERVICE_ADDRESS} kubeadm-token=${BOOTSTRAP_TOKEN} kubeadm-token-ca-hash=${KUBEADM_TOKEN_CA_HASH} kubernetes-version=${KUBERNETES_VERSION} cert-key=${CERT_KEY} control-plane${common_flags}\n"
            printf "${NC}"
            printf "\n"
            printf "\n"
        fi
    else
        printf "\n"
        printf "To add worker nodes to this installation, run the following script on your other nodes:"
        printf "\n"
        printf "${GREEN}    ${prefix}join.sh | sudo bash -s kubernetes-master-address=${API_SERVICE_ADDRESS} kubeadm-token=${BOOTSTRAP_TOKEN} kubeadm-token-ca-hash=${KUBEADM_TOKEN_CA_HASH} kubernetes-version=${KUBERNETES_VERSION}${common_flags}\n"
        printf "${NC}"
        printf "\n"
        printf "\n"
        if [ "$HA_CLUSTER" = "1" ]; then
            printf "\n"
            printf "To add ${GREEN}MASTER${NC} nodes to this installation, run the following script on your other nodes:"
            printf "\n"
            printf "${GREEN}    ${prefix}join.sh | sudo bash -s kubernetes-master-address=${API_SERVICE_ADDRESS} kubeadm-token=${BOOTSTRAP_TOKEN} kubeadm-token-ca-hash=$KUBEADM_TOKEN_CA_HASH kubernetes-version=${KUBERNETES_VERSION} cert-key=${CERT_KEY} control-plane${common_flags}\n"
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
    require_root_user
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

    # ALPHA FLAGS
    if [ -n "$RKE2_VERSION" ]; then
        K8S_DISTRO=rke2
        rke2_main "$@"
        exit 0
    elif [ -n "$K3S_VERSION" ]; then
        K8S_DISTRO=k3s
        k3s_main "$@"
        exit 0
    fi

    export KUBECONFIG=/etc/kubernetes/admin.conf

    is_ha
    parse_kubernetes_target_version
    discover full-cluster
    report_install_start
    trap ctrl_c SIGINT # trap ctrl+c (SIGINT) and handle it by reporting that the user exited intentionally (along with the line/version/etc)
    trap trap_report_error ERR # trap errors and handle it by reporting the error line and parent function
    preflights
    common_prompts
    journald_persistent
    configure_proxy
    configure_no_proxy_preinstall
    ${K8S_DISTRO}_addon_for_each addon_fetch
    if [ -z "$CURRENT_KUBERNETES_VERSION" ]; then
        host_preflights "1" "0" "0"
    else
        host_preflights "1" "0" "1"
    fi
    install_host_dependencies
    get_common
    setup_kubeadm_kustomize
    ${K8S_DISTRO}_addon_for_each addon_pre_init
    discover_pod_subnet
    discover_service_subnet
    configure_no_proxy
    install_cri
    get_shared
    report_upgrade_kubernetes
    report_kubernetes_install
    export SUPPORT_BUNDLE_READY=1 # allow ctrl+c and ERR traps to collect support bundles now that k8s is installed
    type create_registry_service &> /dev/null && create_registry_service # this function is in an optional addon and may be missing
    kurl_init_config
    ${K8S_DISTRO}_addon_for_each addon_install
    helmfile_sync
    post_init
    outro
    package_cleanup

    popd_install_directory

    report_install_success
}

main "$@"
