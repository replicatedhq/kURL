# Kurl Specific RKE Install

RKE2_SHOULD_RESTART=

function rke2_init() {
#     logStep "Initialize Kubernetes"

#     kubernetes_maybe_generate_bootstrap_token

#     API_SERVICE_ADDRESS="$PRIVATE_ADDRESS:6443"
#     if [ "$HA_CLUSTER" = "1" ]; then
#         API_SERVICE_ADDRESS="$LOAD_BALANCER_ADDRESS:$LOAD_BALANCER_PORT"
#     fi

#     local oldLoadBalancerAddress=$(kubernetes_load_balancer_address)
#     if commandExists ekco_handle_load_balancer_address_change_pre_init; then
#         ekco_handle_load_balancer_address_change_pre_init $oldLoadBalancerAddress $LOAD_BALANCER_ADDRESS
#     fi

#     kustomize_kubeadm_init=./kustomize/kubeadm/init
#     CERT_KEY=
#     CERT_KEY_EXPIRY=
#     if [ "$HA_CLUSTER" = "1" ]; then
#         CERT_KEY=$(< /dev/urandom tr -dc a-f0-9 | head -c64)
#         CERT_KEY_EXPIRY=$(TZ="UTC" date -d "+2 hour" --rfc-3339=second | sed 's/ /T/')
#         insert_patches_strategic_merge \
#             $kustomize_kubeadm_init/kustomization.yaml \
#             patch-certificate-key.yaml
#     fi

#     # kustomize can merge multiple list patches in some cases but it is not working for me on the
#     # ClusterConfiguration.apiServer.certSANs list
#     if [ -n "$PUBLIC_ADDRESS" ] && [ -n "$LOAD_BALANCER_ADDRESS" ]; then
#         insert_patches_strategic_merge \
#             $kustomize_kubeadm_init/kustomization.yaml \
#             patch-public-and-load-balancer-address.yaml
#     elif [ -n "$PUBLIC_ADDRESS" ]; then
#         insert_patches_strategic_merge \
#             $kustomize_kubeadm_init/kustomization.yaml \
#             patch-public-address.yaml
#     elif [ -n "$LOAD_BALANCER_ADDRESS" ]; then
#         insert_patches_strategic_merge \
#             $kustomize_kubeadm_init/kustomization.yaml \
#             patch-load-balancer-address.yaml
#     fi

#     # Add kubeadm init patches from addons.
#     for patch in $(ls -1 ${kustomize_kubeadm_init}-patches/* 2>/dev/null || echo); do
#         patch_basename="$(basename $patch)"
#         cp $patch $kustomize_kubeadm_init/$patch_basename
#         insert_patches_strategic_merge \
#             $kustomize_kubeadm_init/kustomization.yaml \
#             $patch_basename
#     done
#     mkdir -p "$KUBEADM_CONF_DIR"
#     kubectl kustomize $kustomize_kubeadm_init > $KUBEADM_CONF_DIR/kubeadm-init-raw.yaml
#     render_yaml_file $KUBEADM_CONF_DIR/kubeadm-init-raw.yaml > $KUBEADM_CONF_FILE

#     # kustomize requires assests have a metadata field while kubeadm config will reject yaml containing it
#     # this uses a go binary found in kurl/cmd/yamlutil to strip the metadata field from the yaml
#     #
#     cp $KUBEADM_CONF_FILE $KUBEADM_CONF_DIR/kubeadm_conf_copy_in
#     $DIR/bin/yamlutil -r -fp $KUBEADM_CONF_DIR/kubeadm_conf_copy_in -yf metadata
#     mv $KUBEADM_CONF_DIR/kubeadm_conf_copy_in $KUBEADM_CONF_FILE

#     cat << EOF >> $KUBEADM_CONF_FILE
# apiVersion: kubelet.config.k8s.io/v1beta1
# kind: KubeletConfiguration
# cgroupDriver: systemd
# ---
# EOF

#     # When no_proxy changes kubeadm init rewrites the static manifests and fails because the api is
#     # restarting. Trigger the restart ahead of time and wait for it to be healthy.
#     if [ -f "/etc/kubernetes/manifests/kube-apiserver.yaml" ] && [ -n "$no_proxy" ] && ! cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep -q "$no_proxy"; then
#         kubeadm init phase control-plane apiserver --config $KUBEADM_CONF_FILE
#         sleep 2
#         if ! spinner_until 60 kubernetes_api_is_healthy; then
#             echo "Failed to wait for kubernetes API restart after no_proxy change" # continue
#         fi
#     fi

#     if [ "$HA_CLUSTER" = "1" ]; then
#         UPLOAD_CERTS="--upload-certs"
#     fi

#     # kubeadm init temporarily taints this node which causes rook to move any mons on it and may
#     # lead to a loss of quorum
#     disable_rook_ceph_operator

#     # since K8s 1.19.1 kubeconfigs point to local API server even in HA setup. When upgrading from
#     # earlier versions and using a load balancer, kubeadm init will bail because the kubeconfigs
#     # already exist pointing to the load balancer
#     rm -rf /etc/kubernetes/*.conf

#     # Regenerate api server cert in case load balancer address changed
#     if [ -f /etc/kubernetes/pki/apiserver.crt ]; then
#         mv -f /etc/kubernetes/pki/apiserver.crt /tmp/
#     fi
#     if [ -f /etc/kubernetes/pki/apiserver.key ]; then
#         mv -f /etc/kubernetes/pki/apiserver.key /tmp/
#     fi

#     set -o pipefail
#     kubeadm init \
#         --ignore-preflight-errors=all \
#         --config $KUBEADM_CONF_FILE \
#         $UPLOAD_CERTS \
#         | tee /tmp/kubeadm-init
#     set +o pipefail

#     if [ -n "$LOAD_BALANCER_ADDRESS" ]; then
#         spinner_until 120 cert_has_san "$PRIVATE_ADDRESS:6443" "$LOAD_BALANCER_ADDRESS"
#     fi

#     spinner_kubernetes_api_stable

    # exportKubeconfig      # This was moved to the setup function
#     KUBEADM_TOKEN_CA_HASH=$(cat /tmp/kubeadm-init | grep 'discovery-token-ca-cert-hash' | awk '{ print $2 }' | head -1)

    wait_for_nodes
    enable_rook_ceph_operator

    DID_INIT_KUBERNETES=1
    # logSuccess "Kubernetes Master Initialized"

    # local currentLoadBalancerAddress=$(kubernetes_load_balancer_address)
    # if [ "$currentLoadBalancerAddress" != "$oldLoadBalancerAddress" ]; then
    #     # restart scheduler and controller-manager on this node so they use the new address
    #     mv /etc/kubernetes/manifests/kube-scheduler.yaml /tmp/ && sleep 1 && mv /tmp/kube-scheduler.yaml /etc/kubernetes/manifests/
    #     mv /etc/kubernetes/manifests/kube-controller-manager.yaml /tmp/ && sleep 1 && mv /tmp/kube-controller-manager.yaml /etc/kubernetes/manifests/
    #     # restart kube-proxies so they use the new address
    #     kubectl -n kube-system delete pods --selector=k8s-app=kube-proxy

    #     if kubernetes_has_remotes; then
    #         local proxyFlag=""
    #         if [ -n "$PROXY_ADDRESS" ]; then
    #             proxyFlag=" -x $PROXY_ADDRESS"
    #         fi
    #         local prefix="curl -sSL${proxyFlag} $KURL_URL/$INSTALLER_ID/"
    #         if [ "$AIRGAP" = "1" ] || [ -z "$KURL_URL" ]; then
    #             prefix="cat "
    #         fi

    #         printf "${YELLOW}\nThe load balancer address has changed. Run the following on all remote nodes to use the new address${NC}\n"
    #         printf "\n"
    #         printf "${GREEN}    ${prefix}tasks.sh | sudo bash -s set-kubeconfig-server https://${currentLoadBalancerAddress}${NC}\n"
    #         printf "\n"
    #         printf "Continue? "
    #         confirmN

    #         if commandExists ekco_handle_load_balancer_address_change_post_init; then
    #             ekco_handle_load_balancer_address_change_post_init $oldLoadBalancerAddress $LOAD_BALANCER_ADDRESS
    #         fi
    #     fi
    # fi

    labelNodes
    kubectl cluster-info

    # create kurl namespace if it doesn't exist
    kubectl get ns kurl 2>/dev/null 1>/dev/null || kubectl create ns kurl 1>/dev/null

    logSuccess "Cluster Initialized"

    # TODO(dans): coredns is deployed through helm -> might need to go through values here
    # configure_coredns

    if commandExists registry_init; then
        registry_init
    fi
}

function rke2_install() {
    local rke2_version="$1"

    export PATH=$PATH:/var/lib/rancher/rke2/bin
    export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
    export CRI_CONFIG_FILE=/var/lib/rancher/rke2/agent/etc/crictl.yaml

    # TODO(ethan): is this still necessary?
    # kubernetes_load_ipvs_modules

    # TODO(ethan): is this still necessary?
    # kubernetes_sysctl_config

    local k8s_semver=
    k8s_semver="$(echo "${rke2_version}" | sed 's/^v\(.*\)-.*$/\1/')"

    # For online always download the rke2.tar.gz bundle.
    # Regardless if host packages are already installed, we always inspect for newer versions
    # and/or re-install any missing or corrupted packages.
    # TODO(ethan): is this comment correct?
    if [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        rke2_get_host_packages_online "${rke2_version}"
        kubernetes_get_conformance_packages_online "${k8s_semver}"
    fi

    rke2_configure

    rke2_install_host_packages "${rke2_version}"

    rke2_load_images "${rke2_version}"

    systemctl enable rke2-server.service
    systemctl start rke2-server.service

    spinner_containerd_is_healthy

    get_shared

    logStep "Installing plugins"
    install_plugins
    logSuccess "Plugins installed"

    # TODO(ethan)
    # install_kustomize

    while [ ! -f /etc/rancher/rke2/rke2.yaml ]; do
        sleep 2
    done

    if [ -d "$DIR/packages/kubernetes-conformance/${k8s_semver}/images" ]; then
        load_images "$DIR/packages/kubernetes-conformance/${k8s_semver}/images"
    fi

    # For Kubectl and Rke2 binaries 
    # NOTE: this is still not in root's path
    if ! grep -q "/var/lib/rancher/rke2/bin" /etc/profile ; then
        echo "export PATH=\$PATH:/var/lib/rancher/rke2/bin" >> /etc/profile
    fi
    if ! grep -q "/var/lib/rancher/rke2/agent/etc/crictl.yaml" /etc/profile ; then
        echo "export CRI_CONFIG_FILE=/var/lib/rancher/rke2/agent/etc/crictl.yaml" >> /etc/profile
    fi

    exportKubeconfig

    logStep "Waiting for Kubernetes"
    # Extending timeout to 5 min based on performance on clean machines.
    if ! spinner_until 300 get_nodes_succeeds ; then
        # this should exit script on non-zero exit code and print error message
        kubectl get nodes 1>/dev/null
    fi

    wait_for_default_namespace
    logSuccess "Kubernetes ready"

    # TODO(dan): Need to figure out how to let users run container tools as non-root

}

function rke2_preamble() {
    printf "${RED}"
    cat << "EOF"
 (                 )               (      ____ 
 )\ )    (      ( /(  (            )\ )  |   / 
(()/(    )\     )\()) )\ )    (   (()/(  |  /  
 /(_))((((_)(  ((_)\ (()/(    )\   /(_)) | /   
(_))_  )\ _ )\  _((_) /(_))_ ((_) (_))   |/    
 |   \ (_)_\(_)| \| |(_)) __|| __|| _ \ (      
 | |) | / _ \  | .` |  | (_ || _| |   / )\     
 |___/ /_/ \_\ |_|\_|   \___||___||_|_\((_)                                                   
EOF
    printf "${NC}\n"
    printf "${RED}YOU ARE NOW INSTALLING RKE2 WITH KURL. THIS FEATURE IS EXPERIMENTAL!${NC}\n"
    printf "${RED}\t- It can be removed at any point in the future.${NC}\n"
    printf "${RED}\t- There are zero guarantees regarding addon compatibility.${NC}\n"
    printf "${RED}\n\nCONTINUING AT YOUR OWN RISK....${NC}\n\n"
}

function rke2_outro() {
    echo
    # if [ -z "$PUBLIC_ADDRESS" ]; then
    #   if [ -z "$PRIVATE_ADDRESS" ]; then
    #     PUBLIC_ADDRESS="<this_server_address>"
    #     PRIVATE_ADDRESS="<this_server_address>"
    #   else
    #     PUBLIC_ADDRESS="$PRIVATE_ADDRESS"
    #   fi
    # fi

    # local proxyFlag=""
    # if [ -n "$PROXY_ADDRESS" ]; then
    #     proxyFlag=" -x $PROXY_ADDRESS"
    # fi

    # local common_flags
    # common_flags="${common_flags}$(get_docker_registry_ip_flag "${DOCKER_REGISTRY_IP}")"
    # common_flags="${common_flags}$(get_additional_no_proxy_addresses_flag "${PROXY_ADDRESS}" "${SERVICE_CIDR},${POD_CIDR}")"
    # common_flags="${common_flags}$(get_kurl_install_directory_flag "${KURL_INSTALL_DIRECTORY_FLAG}")"

    # TODO(dan): move this somewhere into the k8s distro
    # KUBEADM_TOKEN_CA_HASH=$(cat /tmp/kubeadm-init | grep 'discovery-token-ca-cert-hash' | awk '{ print $2 }' | head -1)

    printf "\n"
    printf "\t\t${GREEN}Installation${NC}\n"
    printf "\t\t${GREEN}  Complete ✔${NC}\n"
    addon_outro
    printf "\n"

    # TODO(dan): specific to kubeadm config.
    # kubeconfig_setup_outro  
    
    local prefix="curl -sSL${proxyFlag} $KURL_URL/$INSTALLER_ID/"
    if [ -z "$KURL_URL" ]; then
        prefix="cat "
    fi

    # if [ "$HA_CLUSTER" = "1" ]; then
    #     printf "Master node join commands expire after two hours, and worker node join commands expire after 24 hours.\n"
    #     printf "\n"
    #     if [ "$AIRGAP" = "1" ]; then
    #         printf "To generate new node join commands, run ${GREEN}cat ./tasks.sh | sudo bash -s join_token ha airgap${NC} on an existing master node.\n"
    #     else 
    #         printf "To generate new node join commands, run ${GREEN}${prefix}tasks.sh | sudo bash -s join_token ha${NC} on an existing master node.\n"
    #     fi
    # else
    #     printf "Node join commands expire after 24 hours.\n"
    #     printf "\n"
    #     if [ "$AIRGAP" = "1" ]; then
    #         printf "To generate new node join commands, run ${GREEN}cat ./tasks.sh | sudo bash -s join_token airgap${NC} on this node.\n"
    #     else 
    #         printf "To generate new node join commands, run ${GREEN}${prefix}tasks.sh | sudo bash -s join_token${NC} on this node.\n"
    #     fi
    # fi

    # if [ "$AIRGAP" = "1" ]; then
    #     printf "\n"
    #     printf "To add worker nodes to this installation, copy and unpack this bundle on your other nodes, and run the following:"
    #     printf "\n"
    #     printf "\n"
    #     printf "${GREEN}    cat ./join.sh | sudo bash -s airgap kubernetes-master-address=${API_SERVICE_ADDRESS} kubeadm-token=${BOOTSTRAP_TOKEN} kubeadm-token-ca-hash=${KUBEADM_TOKEN_CA_HASH} kubernetes-version=${KUBERNETES_VERSION}${common_flags}\n"
    #     printf "${NC}"
    #     printf "\n"
    #     printf "\n"
    #     if [ "$HA_CLUSTER" = "1" ]; then
    #         printf "\n"
    #         printf "To add ${GREEN}MASTER${NC} nodes to this installation, copy and unpack this bundle on your other nodes, and run the following:"
    #         printf "\n"
    #         printf "\n"
    #         printf "${GREEN}    cat ./join.sh | sudo bash -s airgap kubernetes-master-address=${API_SERVICE_ADDRESS} kubeadm-token=${BOOTSTRAP_TOKEN} kubeadm-token-ca-hash=${KUBEADM_TOKEN_CA_HASH} kubernetes-version=${KUBERNETES_VERSION} cert-key=${CERT_KEY} control-plane${common_flags}\n"
    #         printf "${NC}"
    #         printf "\n"
    #         printf "\n"
    #     fi
    # else
    #     printf "\n"
    #     printf "To add worker nodes to this installation, run the following script on your other nodes:"
    #     printf "\n"
    #     printf "${GREEN}    ${prefix}join.sh | sudo bash -s kubernetes-master-address=${API_SERVICE_ADDRESS} kubeadm-token=${BOOTSTRAP_TOKEN} kubeadm-token-ca-hash=${KUBEADM_TOKEN_CA_HASH} kubernetes-version=${KUBERNETES_VERSION}${common_flags}\n"
    #     printf "${NC}"
    #     printf "\n"
    #     printf "\n"
    #     if [ "$HA_CLUSTER" = "1" ]; then
    #         printf "\n"
    #         printf "To add ${GREEN}MASTER${NC} nodes to this installation, run the following script on your other nodes:"
    #         printf "\n"
    #         printf "${GREEN}    ${prefix}join.sh | sudo bash -s kubernetes-master-address=${API_SERVICE_ADDRESS} kubeadm-token=${BOOTSTRAP_TOKEN} kubeadm-token-ca-hash=$KUBEADM_TOKEN_CA_HASH kubernetes-version=${KUBERNETES_VERSION} cert-key=${CERT_KEY} control-plane${common_flags}\n"
    #         printf "${NC}"
    #         printf "\n"
    #         printf "\n"
    #     fi
    # fi
}

function rke2_main() {
    local rke2_version="$(echo "${RKE2_VERSION}" | sed 's/+/-/')"

    rke2_preamble  

    # RKE Begin

    # parse_kubernetes_target_version   # TODO(dan): Version only makes sense for kuberntees
    discover full-cluster               # TODO(dan): looks for docker and kubernetes, shouldn't hurt
    # report_install_start              # TODO(dan) remove reporting for now.
    # trap prek8s_ctrl_c SIGINT # trap ctrl+c (SIGINT) and handle it by reporting that the user exited intentionally # TODO(dan) remove reporting for now.
    # preflights                        # TODO(dan): mostly good, but disable for now
    ${K8S_DISTRO}_addon_for_each addon_fetch
    # if [ -z "$CURRENT_KUBERNETES_VERSION" ]; then # TODO (ethan): support for CURRENT_KUBERNETES_VERSION
    #     host_preflights "1" "0" "0"
    # else
    #     host_preflights "1" "0" "1"
    # fi
    common_prompts                      # TODO(dan): shouldn't come into play for RKE2
    journald_persistent
    configure_proxy
    install_host_dependencies
    get_common
    ${K8S_DISTRO}_addon_for_each addon_pre_init
    discover_pod_subnet
    # discover_service_subnet           # TODO(dan): uses kubeadm
    configure_no_proxy

    rke2_install "${rke2_version}"

    # upgrade_kubernetes                # TODO(dan): uses kubectl operator
    
    # kubernetes_host                   # TODO(dan): installs and sets up kubeadm, kubectl
    # setup_kubeadm_kustomize           # TODO(dan): self-explainatory
    # trap k8s_ctrl_c SIGINT # trap ctrl+c (SIGINT) and handle it by asking for a support bundle - only do this after k8s is installed
    ${K8S_DISTRO}_addon_for_each addon_load
    # init                              # See next line
    rke2_init                            # TODO(dan): A mix of Kubeadm stuff and general setup.
    apply_installer_crd
    kurl_init_config
    ${K8S_DISTRO}_addon_for_each addon_install
    # post_init                          # TODO(dan): more kubeadm token setup
    rke2_outro                           
    package_cleanup
    # report_install_success # TODO(dan) remove reporting for now.
}

function rke2_configure() {
    # prevent permission denied error when running kubectl
    if ! grep -qs "^write-kubeconfig-mode:" /etc/rancher/rke2/config.yaml ; then
        mkdir -p /etc/rancher/rke2/
        echo "write-kubeconfig-mode: 644" >> /etc/rancher/rke2/config.yaml
        RKE2_SHOULD_RESTART=1
    fi

    # TODO(ethan): pod cidr
    # TODO(ethan): service cidr
    # TODO(ethan): http proxy
    # TODO(ethan): load balancer
}

function rke2_restart() {
    restart_systemd_and_wait "rke2-server.service"  # TODO(ethan): rke2-agent.service?
}

function rke2_install_host_packages() {
    local rke2_version="$1"

    logStep "Install RKE2 host packages"

    if rke2_host_packages_ok "${rke2_version}"; then
        logSuccess "RKE2 host packages already installed"

        if [ "${RKE2_SHOULD_RESTART}" = "1" ]; then
            rke2_restart
            RKE2_SHOULD_RESTART=0
        fi
        return
    fi

    case "$LSB_DIST" in
        ubuntu)
            bail "RKE2 unsupported on $LSB_DIST Linux"
            ;;

        centos|rhel|amzn|ol)
            case "$LSB_DIST$DIST_VERSION_MAJOR" in
                rhel8|centos8)
                    rpm --upgrade --force --nodeps $DIR/packages/rke-2/${rke2_version}/rhel-8/*.rpm
                    ;;

                *)
                    rpm --upgrade --force --nodeps $DIR/packages/rke-2/${rke2_version}/rhel-7/*.rpm
                    ;;
            esac
        ;;

        *)
            bail "RKE2 install is not supported on ${LSB_DIST} ${DIST_MAJOR}"
            ;;
    esac

    # TODO(ethan): is this still necessary?
    # if [ "$CLUSTER_DNS" != "$DEFAULT_CLUSTER_DNS" ]; then
    #     sed -i "s/$DEFAULT_CLUSTER_DNS/$CLUSTER_DNS/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    # fi

    logSuccess "RKE2 host packages installed"
}

function rke2_host_packages_ok() {
    local rke2_version="$1"

    if ! commandExists kubelet; then
        echo "kubelet command missing - will install host components"
        return 1
    fi
    if ! commandExists kubectl; then
        echo "kubectl command missing - will install host components"
        return 1
    fi

    kubelet --version | grep -q "$(echo $rke2_version | sed "s/-/+/")"
}

function rke2_get_host_packages_online() {
    local rke2_version="$1"

    rm -rf $DIR/packages/rke-2/${rke2_version} # Cleanup broken/incompatible packages from failed runs

    local package="rke-2-${rke2_version}.tar.gz"
    package_download "${package}"
    tar xf "$(package_filepath "${package}")"
}

function rke2_load_images() {
    local rke2_version="$1"

    logStep "Load RKE2 images"

    mkdir -p /var/lib/rancher/rke2/agent/images
    gunzip -c $DIR/packages/rke-2/${rke2_version}/assets/rke2-images.linux-amd64.tar.gz > /var/lib/rancher/rke2/agent/images/rke2-images.linux-amd64.tar

    logSuccess "RKE2 images loaded"
}
