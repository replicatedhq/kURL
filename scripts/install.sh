#!/bin/bash

set -e

MASTER=1
DIR=.

# Magic begin: scripts are inlined for distribution. See "make build/install.sh"
. $DIR/scripts/Manifest
. $DIR/scripts/common/addon.sh
. $DIR/scripts/common/common.sh
. $DIR/scripts/common/discover.sh
. $DIR/scripts/common/docker.sh
. $DIR/scripts/common/kubernetes.sh
. $DIR/scripts/common/object_store.sh
. $DIR/scripts/common/preflights.sh
. $DIR/scripts/common/prompts.sh
. $DIR/scripts/common/proxy.sh
. $DIR/scripts/common/rook.sh
. $DIR/scripts/common/upgrade.sh
. $DIR/scripts/common/utilbinaries.sh
. $DIR/scripts/common/yaml.sh
# Magic end

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

    cat << EOF >> $KUBEADM_CONF_FILE
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
---
EOF

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
    rm -f /etc/kubernetes/*.conf

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

    exportKubeconfig
    KUBEADM_TOKEN_CA_HASH=$(cat /tmp/kubeadm-init | grep 'discovery-token-ca-cert-hash' | awk '{ print $2 }' | head -1)

    waitForNodes
    enable_rook_ceph_operator

    DID_INIT_KUBERNETES=1
    logSuccess "Kubernetes Master Initialized"

    local currentLoadBalancerAddress=$(kubernetes_load_balancer_address)
    if [ "$currentLoadBalancerAddress" != "$oldLoadBalancerAddress" ]; then
        # restart scheduler and controller-manager on this node so they use the new address
        mv /etc/kubernetes/manifests/kube-scheduler.yaml /tmp/ && sleep 1 && mv /tmp/kube-scheduler.yaml /etc/kubernetes/manifests/
        mv /etc/kubernetes/manifests/kube-controller-manager.yaml /tmp/ && sleep 1 && mv /tmp/kube-controller-manager.yaml /etc/kubernetes/manifests/
        if kubernetes_has_remotes; then
            local proxyFlag=""
            if [ -n "$PROXY_ADDRESS" ]; then
                proxyFlag=" -x $PROXY_ADDRESS"
            fi
            local prefix="curl -sSL${proxyFlag} $KURL_URL/$INSTALLER_ID/"
            if [ "$AIRGAP" = "1" ] || [ -z "$KURL_URL" ]; then
                prefix="cat "
            fi

            printf "${YELLOW}\nThe load balancer address has changed. Run the following on all remote nodes to use the new address${NC}\n"
            printf "\n"
            printf "${GREEN}    ${prefix}tasks.sh | sudo bash -s set-kubeconfig-server https://${currentLoadBalancerAddress}${NC}\n"
            printf "\n"
            printf "Continue? "
            confirmY " "

            if commandExists ekco_handle_load_balancer_address_change_post_init; then
                ekco_handle_load_balancer_address_change_post_init $oldLoadBalancerAddress $LOAD_BALANCER_ADDRESS
            fi
        fi
    fi

    labelNodes
    kubectl cluster-info
    logSuccess "Cluster Initialized"

    if commandExists containerd_registry_init; then
        containerd_registry_init
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
        --from-literal=pod_cidr="$POD_CIDR"
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

    local dockerRegistryIP=""
    if [ -n "$DOCKER_REGISTRY_IP" ]; then
        dockerRegistryIP=" docker-registry-ip=$DOCKER_REGISTRY_IP"
    fi

    local proxyFlag=""
    local noProxyAddrs=""
    if [ -n "$PROXY_ADDRESS" ]; then
        proxyFlag=" -x $PROXY_ADDRESS"
        noProxyAddrs=" additional-no-proxy-addresses=${SERVICE_CIDR},${POD_CIDR}"
    fi

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
    
    local prefix="curl -sSL${proxyFlag} $KURL_URL/$INSTALLER_ID/"
    if [ -z "$KURL_URL" ]; then
        prefix="cat "
    fi

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
        printf "${GREEN}    cat ./join.sh | sudo bash -s airgap kubernetes-master-address=${API_SERVICE_ADDRESS} kubeadm-token=${BOOTSTRAP_TOKEN} kubeadm-token-ca-hash=${KUBEADM_TOKEN_CA_HASH} kubernetes-version=${KUBERNETES_VERSION}${dockerRegistryIP}${noProxyAddrs}\n"
        printf "${NC}"
        printf "\n"
        printf "\n"
        if [ "$HA_CLUSTER" = "1" ]; then
            printf "\n"
            printf "To add ${GREEN}MASTER${NC} nodes to this installation, copy and unpack this bundle on your other nodes, and run the following:"
            printf "\n"
            printf "\n"
            printf "${GREEN}    cat ./join.sh | sudo bash -s airgap kubernetes-master-address=${API_SERVICE_ADDRESS} kubeadm-token=${BOOTSTRAP_TOKEN} kubeadm-token-ca-hash=${KUBEADM_TOKEN_CA_HASH} kubernetes-version=${KUBERNETES_VERSION} cert-key=${CERT_KEY} control-plane${dockerRegistryIP}${noProxyAddrs}\n"
            printf "${NC}"
            printf "\n"
            printf "\n"
        fi
    else
        printf "\n"
        printf "To add worker nodes to this installation, run the following script on your other nodes:"
        printf "\n"
        printf "${GREEN}    ${prefix}join.sh | sudo bash -s kubernetes-master-address=${API_SERVICE_ADDRESS} kubeadm-token=${BOOTSTRAP_TOKEN} kubeadm-token-ca-hash=${KUBEADM_TOKEN_CA_HASH} kubernetes-version=${KUBERNETES_VERSION}${dockerRegistryIP}${noProxyAddrs}\n"
        printf "${NC}"
        printf "\n"
        printf "\n"
        if [ "$HA_CLUSTER" = "1" ]; then
            printf "\n"
            printf "To add ${GREEN}MASTER${NC} nodes to this installation, run the following script on your other nodes:"
            printf "\n"
            printf "${GREEN}    ${prefix}join.sh | sudo bash -s kubernetes-master-address=${API_SERVICE_ADDRESS} kubeadm-token=${BOOTSTRAP_TOKEN} kubeadm-token-ca-hash=$KUBEADM_TOKEN_CA_HASH kubernetes-version=${KUBERNETES_VERSION} cert-key=${CERT_KEY} control-plane${dockerRegistryIP}${noProxyAddrs}\n"
            printf "${NC}"
            printf "\n"
            printf "\n"
        fi
    fi
}

function main() {
    export KUBECONFIG=/etc/kubernetes/admin.conf
    requireRootUser
    get_patch_yaml "$@"
    yaml_airgap
    proxy_bootstrap
    download_util_binaries
    merge_yaml_specs
    apply_bash_flag_overrides "$@"
    parse_yaml_into_bash_variables
    parse_kubernetes_target_version
    discover full-cluster
    preflights
    prompts
    configure_proxy
    addon_for_each addon_pre_init
    discover_pod_subnet
    discover_service_subnet
    configure_no_proxy
    install_cri
    get_shared
    upgrade_kubernetes
    kubernetes_host
    setup_kubeadm_kustomize
    addon_for_each addon_load
    init
    apply_installer_crd
    addon_for_each addon_install
    post_init
    outro
}

main "$@"
