# Kurl Specific K3S Install

K3S_SHOULD_RESTART=

function k3s_init() {
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
    #         confirmY " "

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

    if commandExists registry_containerd_init; then
        registry_containerd_init
    fi
}

function k3s_install() {
    local k3s_version="$1"

    # TODO(ethan): is this still necessary?
    # kubernetes_sysctl_config

    # For online always download the k3s.tar.gz bundle.
    # Regardless if host packages are already installed, we always inspect for newer versions
    # and/or re-install any missing or corrupted packages.
    # TODO(ethan): is this comment correct?
    if [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        k3s_get_host_packages_online "${k3s_version}"
    fi

    k3s_configure
    k3s_install_host_packages "${k3s_version}"
    k3s_load_images "${k3s_version}"

    if [ "$MASTER" == "1" ]; then
        k3s_server_setup_systemd_service
    else 
        # TOOD (dan): agent nodes not supported.
        bail "Agent nodes for k3s are currently unsupported"
    fi

    k3s_create_symlinks
    k3s_modify_profiled
    
    spinner_containerd_is_healthy
    
    get_shared

    logStep "Installing plugins"
    install_plugins
    logSuccess "Plugins installed"

    # TODO(ethan)
    # install_kustomize

    # TODO(dan) do I need this
    while [ ! -f /etc/rancher/k3s/k3s.yaml ]; do
        sleep 2
    done

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

function k3s_preamble() {
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
    printf "${RED}YOU ARE NOW INSTALLING K3S WITH KURL. THIS FEATURE IS EXPERIMENTAL!${NC}\n"
    printf "${RED}\t- It can be removed at any point in the future.${NC}\n"
    printf "${RED}\t- There are zero guarantees regarding addon compatibility.${NC}\n"
    printf "${RED}\n\nCONTINUING AT YOUR OWN RISK....${NC}\n\n"
}

function k3s_outro() {
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

function k3s_main() {
    local k3s_version="$(echo "${K3S_VERSION}" | sed 's/+/-/')"

    k3s_preamble  

    # K3S Begin

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
    prompts                             # TODO(dan): shouldn't come into play for K3S
    journald_persistent
    configure_proxy
    install_host_dependencies
    ${K8S_DISTRO}_addon_for_each addon_pre_init
    discover_pod_subnet
    # discover_service_subnet           # TODO(dan): uses kubeadm
    configure_no_proxy

    k3s_install "${k3s_version}"

    # upgrade_kubernetes                # TODO(dan): uses kubectl operator
    
    # kubernetes_host                   # TODO(dan): installs and sets up kubeadm, kubectl
    # setup_kubeadm_kustomize           # TODO(dan): self-explainatory
    # trap k8s_ctrl_c SIGINT # trap ctrl+c (SIGINT) and handle it by asking for a support bundle - only do this after k8s is installed
    ${K8S_DISTRO}_addon_for_each addon_load
    # init                              # See next line
    k3s_init                            # TODO(dan): A mix of Kubeadm stuff and general setup.
    apply_installer_crd
    type create_registry_service &> /dev/null && create_registry_service # this function is in an optional addon and may be missing
    ${K8S_DISTRO}_addon_for_each addon_install
    # post_init                          # TODO(dan): more kubeadm token setup
    k3s_outro                            
    package_cleanup
    # report_install_success # TODO(dan) remove reporting for now.
}

function k3s_configure() {

    if ! grep -qs "^write-kubeconfig:" /etc/rancher/k3s/config.yaml ; then
        mkdir -p /etc/rancher/k3s/
        echo "write-kubeconfig: \"/etc/rancher/k3s/k3s.yaml\"" >> /etc/rancher/k3s/config.yaml        
        K3S_SHOULD_RESTART=1
    fi

    # prevent permission denied error when running kubectl
    if ! grep -qs "^write-kubeconfig-mode:" /etc/rancher/k3s/config.yaml ; then
        mkdir -p /etc/rancher/k3s/
        echo "write-kubeconfig-mode: 644" >> /etc/rancher/k3s/config.yaml
        K3S_SHOULD_RESTART=1
    fi

    # TODO(ethan): pod cidr
    # TODO(ethan): service cidr
    # TODO(ethan): http proxy
    # TODO(ethan): load balancer
}

function k3s_restart() {
    restart_systemd_and_wait "k3s-server.service"  # TODO(ethan): k3s-agent.service?
}

function k3s_install_host_packages() {
    local k3s_version="$1"

    logStep "Install K3S host packages"

    if k3s_host_packages_ok "${k3s_version}"; then
        logSuccess "K3S host packages already installed"

        if [ "${K3S_SHOULD_RESTART}" = "1" ]; then
            k3s_restart
            K3S_SHOULD_RESTART=0
        fi
        return
    fi

    # install the selinux policy
    # TODO (dan): need to integrate this with SELinux settings in install.sh
    if [ -n "$K3S_SELINUX_ENABLED" ]; then
        case "$LSB_DIST" in
            ubuntu)
                bail "K3S unsupported on $LSB_DIST Linux"
                ;;

            centos|rhel|amzn|ol)
                case "$LSB_DIST$DIST_VERSION_MAJOR" in
                    rhel8|centos8)
                        rpm --upgrade --force --nodeps $DIR/packages/k3s/${k3s_version}/rhel-8/*.rpm
                        ;;

                    *)
                        rpm --upgrade --force --nodeps $DIR/packages/k3s/${k3s_version}/rhel-7/*.rpm
                        ;;
                esac
            ;;

            *)
                bail "K3S install is not supported on ${LSB_DIST} ${DIST_MAJOR}"
            ;;
        esac
    fi
    
    # installs the k3s binary
    cp $DIR/packages/k-3-s/${k3s_version}/assets/k3s /usr/local/bin/
    chmod 755 /usr/local/bin/k3s

    # TODO(ethan): is this still necessary?
    # if [ "$CLUSTER_DNS" != "$DEFAULT_CLUSTER_DNS" ]; then
    #     sed -i "s/$DEFAULT_CLUSTER_DNS/$CLUSTER_DNS/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    # fi

    logSuccess "K3S host packages installed"
}

function k3s_host_packages_ok() {
    local k3s_version="$1"

    if ! commandExists k3s; then
        echo "k3s command missing - will install host components"
        return 1
    fi

    kubelet --version | grep -q "$(echo $k3s_version | sed "s/-/+/")"
}

function k3s_get_host_packages_online() {
    local k3s_version="$1"

    rm -rf $DIR/packages/k3s/${k3s_version} # Cleanup broken/incompatible packages from failed runs

    local package="k-3-s-${k3s_version}.tar.gz" 
    package_download "${package}"
    tar xf "$(package_filepath "${package}")"
}

function k3s_load_images() {
    local k3s_version="$1"

    logStep "Load K3S images"

    mkdir -p /var/lib/rancher/k3s/agent/images
    gunzip -c $DIR/packages/k-3-s/${k3s_version}/assets/k3s-images.linux-amd64.tar.gz > /var/lib/rancher/k3s/agent/images/k3s-images.linux-amd64.tar

    logSuccess "K3S images loaded"
}

function k3s_server_setup_systemd_service() {

    if [ -f "/etc/systemd/system/k3s-server.service" ]; then
        logSubstep "Systemd service for the K3S Server already exists. Skipping."
        return
    fi 

    logStep "Creating K3S Server Systemd Service"

    k3s_create_env_file
    # Created Systemd unit from https://get.k3s.io/
    # TODO (dan): check if this should be a server or agent
    tee /etc/systemd/system/k3s-server.service > /dev/null  <<EOF
[Unit]
Description=Lightweight Kubernetes
Documentation=https://k3s.io
Wants=network-online.target
After=network-online.target

[Install]
WantedBy=multi-user.target

[Service]
Type=exec
EnvironmentFile=/etc/systemd/system/k3s-server.env
KillMode=process
Delegate=yes
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s
ExecStartPre=-/sbin/modprobe br_netfilter
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/k3s \\
    server

EOF
    
    systemctl daemon-reload
    systemctl start k3s-server.service 
    systemctl enable k3s-server.service 

    logSuccess "K3S Service created"
}

function k3s_create_env_file() {
    local fileK3sEnv=/etc/systemd/system/k3s-server.env
    echo "Creating environment file ${fileK3sEnv}"
    UMASK=$(umask)
    umask 0377
    env | grep '^K3S_' | tee ${fileK3sEnv} >/dev/null
    env | egrep -i '^(NO|HTTP|HTTPS)_PROXY' | tee -a ${fileK3sEnv} >/dev/null
    umask $UMASK
}

function k3s_create_symlinks() {
    local binDir=/usr/local/bin

    for cmd in kubectl crictl ctr; do
        if [ ! -e ${binDir}/${cmd} ] || [ "${INSTALL_K3S_SYMLINK}" = force ]; then
            which_cmd=$(which ${cmd} 2>/dev/null || true)
            if [ -z "${which_cmd}" ] || [ "${INSTALL_K3S_SYMLINK}" = force ]; then
                echo "Creating ${binDir}/${cmd} symlink to k3s"
                ln -sf k3s ${binDir}/${cmd}
            else
                echo "Skipping ${binDir}/${cmd} symlink to k3s, command exists in PATH at ${which_cmd}"
            fi
        else
            echo "Skipping ${binDir}/${cmd} symlink to k3s, already exists"
        fi
    done
}

function k3s_modify_profiled() {

    # NOTE: this is still not in the path for sudo
    if [ ! -f "/etc/profile.d/k3s.sh" ]; then
        tee /etc/profile.d/k3s.sh > /dev/null <<EOF
export CRI_CONFIG_FILE=/var/lib/rancher/k3s/agent/etc/crictl.yaml
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

if [ -f "/etc/centos-release" ] || [ -f "/etc/redhat-release" ]; then
        pathmunge /usr/local/bin
else
        export PATH=$PATH:/usr/local/bin
fi
EOF
    fi

    source /etc/profile
}
