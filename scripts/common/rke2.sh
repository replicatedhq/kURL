 # Alpha - 2021.01.22
 
 ######################################################
 # This is a copy of the Rancher install script
 ######################################################
 # COPY BEGINS HERE 
 
#  set -e

# if [ "${DEBUG}" = 1 ]; then
#     set -x
# fi

# Usage:
#   curl ... | ENV_VAR=... sh -
#       or
#   ENV_VAR=... ./install.sh


# Environment variables:

#   - INSTALL_RKE2_CHANNEL
#     Channel to use for fetching rke2 download URL.
#     Defaults to 'latest'.

#   - INSTALL_RKE2_METHOD
#     The installation method to use.
#     Default is on RPM-based systems is "rpm", all else "tar".

#   - INSTALL_RKE2_TYPE
#     Type of rke2 service. Can be either "server" or "agent".
#     Default is "server".

#   - INSTALL_RKE2_VERSION
#     Version of rke2 to download from github.

#   - INSTALL_RKE2_RPM_RELEASE_VERSION
#     Version of the rke2 RPM release to install.
#     Format would be like "1.el7" or "2.el8"



# info logs the given argument at info log level.
info() {
    echo "[INFO] " "$@"
}

# warn logs the given argument at warn log level.
warn() {
    echo "[WARN] " "$@" >&2
}

# fatal logs the given argument at fatal log level.
fatal() {
    echo "[ERROR] " "$@" >&2
    if [ -n "${SUFFIX}" ]; then
        echo "[ALT] Please visit 'https://github.com/rancher/rke2/releases' directly and download the latest rke2-installer.${SUFFIX}.run" >&2
    fi
    exit 1
}

# setup_env defines needed environment variables.
setup_env() {
    INSTALL_RKE2_GITHUB_URL="https://github.com/rancher/rke2"
    # --- bail if we are not root ---
    if [ ! $(id -u) -eq 0 ]; then
        fatal "You need to be root to perform this install"
    fi

    # --- make sure install channel has a value
    if [ -z "${INSTALL_RKE2_CHANNEL}" ]; then
        INSTALL_RKE2_CHANNEL="stable"
    fi

    # --- make sure install type has a value
    if [ -z "${INSTALL_RKE2_TYPE}" ]; then
        INSTALL_RKE2_TYPE="server"
    fi

    # --- use yum install method if available by default
    if [ -z "${INSTALL_RKE2_METHOD}" ] && command -v yum >/dev/null 2>&1; then
        INSTALL_RKE2_METHOD=yum
    fi
}

# setup_arch set arch and suffix,
# fatal if architecture not supported.
setup_arch() {
    case ${ARCH:=$(uname -m)} in
    amd64)
        ARCH=amd64
        SUFFIX=$(uname -s | tr '[:upper:]' '[:lower:]')-${ARCH}
        ;;
    x86_64)
        ARCH=amd64
        SUFFIX=$(uname -s | tr '[:upper:]' '[:lower:]')-${ARCH}
        ;;
    *)
        fatal "unsupported architecture ${ARCH}"
        ;;
    esac
}

# verify_downloader verifies existence of
# network downloader executable.
verify_downloader() {
    cmd="$(command -v "${1}")"
    if [ -z "${cmd}" ]; then
        return 1
    fi
    if [ ! -x "${cmd}" ]; then
        return 1
    fi

    # Set verified executable as our downloader program and return success
    DOWNLOADER=${cmd}
    return 0
}

# setup_tmp creates a temporary directory
# and cleans up when done.
setup_tmp() {
    TMP_DIR=$(mktemp -d -t rke2-install.XXXXXXXXXX)
    TMP_CHECKSUMS=${TMP_DIR}/rke2.checksums
    TMP_TARBALL=${TMP_DIR}/rke2.tarball
    cleanup() {
        code=$?
        set +e
        trap - EXIT
        rm -rf "${TMP_DIR}"
        exit $code
    }
    trap cleanup INT EXIT
}

# --- use desired rke2 version if defined or find version from channel ---
get_release_version() {
    if [ -n "${INSTALL_RKE2_COMMIT}" ]; then
        version="commit ${INSTALL_RKE2_COMMIT}"
    elif [ -n "${INSTALL_RKE2_VERSION}" ]; then
        version=${INSTALL_RKE2_VERSION}
    else
        info "finding release for channel ${INSTALL_RKE2_CHANNEL}"
        INSTALL_RKE2_CHANNEL_URL=${INSTALL_RKE2_CHANNEL_URL:-'https://update.rke2.io/v1-release/channels'}
        version_url="${INSTALL_RKE2_CHANNEL_URL}/${INSTALL_RKE2_CHANNEL}"
        case ${DOWNLOADER} in
        *curl)
            version=$(${DOWNLOADER} -w "%{url_effective}" -L -s -S ${version_url} -o /dev/null | sed -e 's|.*/||')
            ;;
        *wget)
            version=$(${DOWNLOADER} -SqO /dev/null ${version_url} 2>&1 | grep -i Location | sed -e 's|.*/||')
            ;;
        *)
            fatal "Unsupported downloader executable '${DOWNLOADER}'"
            ;;
        esac
        INSTALL_RKE2_VERSION="${version}"
    fi
}

# download downloads from github url.
download() {
    if [ $# -ne 2 ]; then
        fatal "download needs exactly 2 arguments"
    fi

    case ${DOWNLOADER} in
    *curl)
        curl -o "$1" -fsSL "$2"
        ;;
    *wget)
        wget -qO "$1" "$2"
        ;;
    *)
        fatal "downloader executable not supported: '${DOWNLOADER}'"
        ;;
    esac

    # Abort if download command failed
    if [ $? -ne 0 ]; then
        fatal "download failed"
    fi
}

# download_checksums downloads hash from github url.
download_checksums() {
    if [ -n "${INSTALL_RKE2_COMMIT}" ]; then
        fatal "downloading by commit is currently not supported"
        # CHECKSUMS_URL=${STORAGE_URL}/rke2${SUFFIX}-${INSTALL_RKE2_COMMIT}.sha256sum
    else
        CHECKSUMS_URL=${INSTALL_RKE2_GITHUB_URL}/releases/download/${INSTALL_RKE2_VERSION}/sha256sum-${ARCH}.txt
    fi
    info "downloading checksums at ${CHECKSUMS_URL}"
    download "${TMP_CHECKSUMS}" "${CHECKSUMS_URL}"
    CHECKSUM_EXPECTED=$(grep "rke2.${SUFFIX}.tar.gz" "${TMP_CHECKSUMS}" | awk '{print $1}')
}

# download_tarball downloads binary from github url.
download_tarball() {
    if [ -n "${INSTALL_RKE2_COMMIT}" ]; then
        fatal "downloading by commit is currently not supported"
        # TARBALL_URL=${STORAGE_URL}/rke2-installer.${SUFFIX}-${INSTALL_RKE2_COMMIT}.run
    else
        TARBALL_URL=${INSTALL_RKE2_GITHUB_URL}/releases/download/${INSTALL_RKE2_VERSION}/rke2.${SUFFIX}.tar.gz
    fi
    info "downloading tarball at ${TARBALL_URL}"
    download "${TMP_TARBALL}" "${TARBALL_URL}"
}

# verify_tarball verifies the downloaded installer checksum.
verify_tarball() {
    info "verifying installer"
    CHECKSUM_ACTUAL=$(sha256sum "${TMP_TARBALL}" | awk '{print $1}')
    if [ "${CHECKSUM_EXPECTED}" != "${CHECKSUM_ACTUAL}" ]; then
        fatal "download sha256 does not match ${CHECKSUM_EXPECTED}, got ${CHECKSUM_ACTUAL}"
    fi
}
unpack_tarball() {
    info "unpacking tarball file"
    mkdir -p /usr/local
    tar xzf $TMP_TARBALL -C /usr/local
}

do_install_rpm() {
    maj_ver="7"
    if [ -r /etc/redhat-release ] || [ -r /etc/centos-release ] || [ -r /etc/oracle-release ]; then
        dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
        maj_ver=$(echo "$dist_version" | sed -E -e "s/^([0-9]+)\.?[0-9]*$/\1/")
        case ${maj_ver} in
            7|8)
                :
                ;;
            *) # In certain cases, like installing on Fedora, maj_ver will end up being something that is not 7 or 8
                maj_ver="7"
                ;;
        esac
    fi
    case "${INSTALL_RKE2_CHANNEL}" in
        v*.*)
            # We are operating with a version-based channel, so we should parse our version out
            rke2_majmin=$(echo "${INSTALL_RKE2_CHANNEL}" | sed -E -e "s/^v([0-9]+\.[0-9]+).*/\1/")
            rke2_rpm_channel=$(echo "${INSTALL_RKE2_CHANNEL}" | sed -E -e "s/^v[0-9]+\.[0-9]+-(.*)/\1/")
            # If our regex fails to capture a "sane" channel out of the specified channel, fall back to `stable`
            if [ "${rke2_rpm_channel}" = ${INSTALL_RKE2_CHANNEL} ]; then
                info "using stable RPM repositories"
                rke2_rpm_channel="stable"
            fi
            ;;
        *)
            get_release_version
            rke2_majmin=$(echo "${INSTALL_RKE2_VERSION}" | sed -E -e "s/^v([0-9]+\.[0-9]+).*/\1/")
            rke2_rpm_channel=${1}
            ;;
    esac
    info "using ${rke2_majmin} series from channel ${rke2_rpm_channel}"
    rpm_site="rpm.rancher.io"
    if [ "${rke2_rpm_channel}" = "testing" ]; then
        rpm_site="rpm-${rke2_rpm_channel}.rancher.io"
    fi
    rm -f /etc/yum.repos.d/rancher-rke2*.repo
    cat <<-EOF >"/etc/yum.repos.d/rancher-rke2.repo"
[rancher-rke2-common-${rke2_rpm_channel}]
name=Rancher RKE2 Common (${1})
baseurl=https://${rpm_site}/rke2/${rke2_rpm_channel}/common/centos/${maj_ver}/noarch
enabled=1
gpgcheck=1
gpgkey=https://${rpm_site}/public.key
[rancher-rke2-${rke2_majmin}-${rke2_rpm_channel}]
name=Rancher RKE2 ${rke2_majmin} (${1})
baseurl=https://${rpm_site}/rke2/${rke2_rpm_channel}/${rke2_majmin}/centos/${maj_ver}/x86_64
enabled=1
gpgcheck=1
gpgkey=https://${rpm_site}/public.key
EOF
    if [ -z ${INSTALL_RKE2_VERSION} ]; then
        yum -y install "rke2-${INSTALL_RKE2_TYPE}"
    else
        rke2_rpm_version=$(echo "${INSTALL_RKE2_VERSION}" | sed -E -e "s/[\+-]/~/g" | sed -E -e "s/v(.*)/\1/")
        if [ -n "${INSTALL_RKE2_RPM_RELEASE_VERSION}" ]; then
            yum -y install "rke2-${INSTALL_RKE2_TYPE}-${rke2_rpm_version}-${INSTALL_RKE2_RPM_RELEASE_VERSION}"
        else
            yum -y install "rke2-${INSTALL_RKE2_TYPE}-${rke2_rpm_version}"
        fi
    fi
}

do_install_tar() {
    setup_tmp
    get_release_version
    info "using ${INSTALL_RKE2_VERSION} as release"
    download_checksums
    download_tarball
    verify_tarball
    unpack_tarball
}

rke_online_install() {
    setup_env
    setup_arch
    verify_downloader curl || verify_downloader wget || fatal "can not find curl or wget for downloading files"

    case ${INSTALL_RKE2_METHOD} in
    yum | rpm | dnf)
        do_install_rpm "${INSTALL_RKE2_CHANNEL}"
        ;;
    tar | tarball)
        do_install_tar "${INSTALL_RKE2_CHANNEL}"
        ;;
    *)
        do_install_tar "${INSTALL_RKE2_CHANNEL}"
        ;;
    esac
}

# COPY ENDS HERE 
######################################################
# This is a copy of the Rancher install script
######################################################
 

# Kurl Specific RKE Install

function rke_init() {
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
#     rm -f /etc/kubernetes/*.conf

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

    # TODO(dans): need to figure out how to configute the embedded containerd in RKE2
    # if commandExists containerd_registry_init; then
    #     containerd_registry_init
    # fi
}

rke_install() {
    # TODO(ethan): this is a kurl dependency, not rke2
    yum install -y openssl

    # Install RKE using RKE Script
    # TODO(dan): Pull a specific version of RKE
    # curl -sfL https://get.rke2.io -o rke_tmp_installer.sh
    rke_online_install

    # Enable service
    systemctl enable rke2-server.service
    systemctl start rke2-server.service

    while [ ! -f /etc/rancher/rke2/rke2.yaml ]; do
        sleep 2
    done

    # For Kubectl and Rke2 binaries 
    echo "export PATH=\$PATH:/var/lib/rancher/rke2/bin" | tee -a /etc/profile > /dev/null
    export PATH=$PATH:/var/lib/rancher/rke2/bin
    export KUBECONFIG=/etc/rancher/rke2/rke2.yaml   # TODO(dan): move this to exportKubeconfig?

    # TODO(dan): moved from init
    exportKubeconfig

    echo "Waiting for Kubernetes"
    wait_for_nodes
    wait_for_default_namespace

    # Install Kustomize and KREW
    # Not needed ATM....

    # TODO(dan): Probably need to install crictl since you can actually config the tool
    # https://github.com/kubernetes-sigs/cri-tools/blob/master/docs/crictl.md
    # VERSION="v1.20.0"
    # curl -L https://github.com/kubernetes-sigs/cri-tools/releases/download/$VERSION/crictl-${VERSION}-linux-amd64.tar.gz --output crictl-${VERSION}-linux-amd64.tar.gz
    # tar zxvf crictl-$VERSION-linux-amd64.tar.gz -C /usr/local/bin
    # rm -f crictl-$VERSION-linux-amd64.tar.gz
    #
    # tee -a /etc/crictl.yaml > /dev/null <<EOT
    # runtime-endpoint: unix:///run/k3s/containerd/containerd.sock
    # image-endpoint: unix:///run/k3s/containerd/containerd.sock
    # EOT

    # TODO(dan): Need to figure out how to let users run container tools as non-root

}

function rke_preamble() {
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
    printf "${RED}\t- There is no stability in RKE version installed.${NC}\n"
    printf "${RED}\n\nCONTINUING AT YOUR OWN RISK....${NC}\n\n"
}

function rke_outro() {
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

    # TODO(dan): move this somewhere into the k8s distro
    # KUBEADM_TOKEN_CA_HASH=$(cat /tmp/kubeadm-init | grep 'discovery-token-ca-cert-hash' | awk '{ print $2 }' | head -1)

    printf "\n"
    printf "\t\t${GREEN}Installation${NC}\n"
    printf "\t\t${GREEN}  Complete ✔${NC}\n"
    addon_outro
    printf "\n"

    # TODO(dan): specific to kubeadm config.
    # kubeconfig_setup_outro  
    
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

function rke_main() {
    INSTALL_RKE2_VERSION="${RKE2_VERSION}"

    # Alpha Checks for RKE2
    if [ "$AIRGAP" = "1" ]; then
        bail "Airgapped mode is not supported for RKE2."
    fi

    detectLsbDist   # This is redundant with the 'discover' function below
    if [ "$LSB_DIST" != "centos" ]; then
        bail "Only Centos is currently supported for RKE2."
    fi

    rke_preamble  

    # RKE Begin

    # parse_kubernetes_target_version   # TODO(dan): Version only makes sense for kuberntees
    discover full-cluster               # TODO(dan): looks for docker and kubernetes, shouldn't hurt
    # report_install_start              # TODO(dan) remove reporting for now.
    # trap prek8s_ctrl_c SIGINT # trap ctrl+c (SIGINT) and handle it by reporting that the user exited intentionally # TODO(dan) remove reporting for now.
    # preflights                        # TODO(dan): mostly good, but disable for now
    prompts                             # TODO(dan): shouldn't come into play for RKE2
    journald_persistent
    configure_proxy
    addon_for_each addon_pre_init
    discover_pod_subnet
    # discover_service_subnet           # TODO(dan): uses kubeadm
    configure_no_proxy
    # install_cri                       # TODO(dan): not needed for RKE2

    rke_install

    get_shared                          # TODO(dan): Docker or CRI needs to be setup for this.
    # upgrade_kubernetes                # TODO(dan): uses kubectl operator
    
    # kubernetes_host                   # TODO(dan): installs and sets up kubeadm, kubectl
    # setup_kubeadm_kustomize           # TODO(dan): self-explainatory
    # trap k8s_ctrl_c SIGINT # trap ctrl+c (SIGINT) and handle it by asking for a support bundle - only do this after k8s is installed
    addon_for_each addon_load
    # init                              # See next line
    rke_init                            # TODO(dan): A mix of Kubeadm stuff and general setup.
    apply_installer_crd
    type create_registry_service &> /dev/null && create_registry_service # this function is in an optional addon and may be missing
    addon_for_each addon_install
    # post_init                          # TODO(dan): more kubeadm token setup
    # outro                              # See next line
    rke_outro                            # TODO(dan): modified this to remove kubeadm stuff
    # report_install_success # TODO(dan) remove reporting for now.
}