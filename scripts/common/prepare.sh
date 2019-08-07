
function prepare() {
    loadIPVSKubeProxyModules

    exportProxy
    # kubeadm requires this in the environment to reach the K8s API server
    export no_proxy="$NO_PROXY_ADDRESSES"

    if [ "$SKIP_DOCKER_INSTALL" != "1" ]; then
        if [ "$OFFLINE_DOCKER_INSTALL" != "1" ]; then
            installDockerOnline "$DOCKER_VERSION" "$MIN_DOCKER_VERSION"

            semverParse "$DOCKER_VERSION"
            if [ "$major" -ge "17" ]; then
                lockPackageVersion docker-ce
            fi
        else
            installDockerOffline
            systemctl enable docker
            systemctl start docker
        fi
        checkDockerStorageDriver "$HARD_FAIL_ON_LOOPBACK"
    fi

    if [ "$NO_PROXY" != "1" ] && [ -n "$PROXY_ADDRESS" ]; then
        requireDockerProxy
    fi

    if [ "$RESTART_DOCKER" = "1" ]; then
        restartDocker
    fi

    if [ "$NO_PROXY" != "1" ] && [ -n "$PROXY_ADDRESS" ]; then
        checkDockerProxyConfig
    fi

    installKubernetesComponents "$KUBERNETES_VERSION"

    if [ "$AIRGAP" = "1" ]; then
        airgapLoadKubernetesImages
    fi

    return 0
}

loadIPVSKubeProxyModules() {
    if [ "$IPVS" != "1" ]; then
        return
    fi
    if lsmod | grep -q ip_vs ; then
        return
    fi

    modprobe nf_conntrack_ipv4
    modprobe ip_vs
    modprobe ip_vs_rr
    modprobe ip_vs_wrr
    modprobe ip_vs_sh

    echo 'nf_conntrack_ipv4' > /etc/modules-load.d/replicated-ipvs.conf
    echo 'ip_vs' >> /etc/modules-load.d/replicated-ipvs.conf
    echo 'ip_vs_rr' >> /etc/modules-load.d/replicated-ipvs.conf
    echo 'ip_vs_wrr' >> /etc/modules-load.d/replicated-ipvs.conf
    echo 'ip_vs_sh' >> /etc/modules-load.d/replicated-ipvs.conf
}

exportProxy() {
    if [ -z "$PROXY_ADDRESS" ]; then
        return
    fi
    if [ -z "$http_proxy" ]; then
       export http_proxy=$PROXY_ADDRESS
    fi
    if [ -z "$https_proxy" ]; then
       export https_proxy=$PROXY_ADDRESS
    fi
    if [ -z "$HTTP_PROXY" ]; then
       export HTTP_PROXY=$PROXY_ADDRESS
    fi
    if [ -z "$HTTPS_PROXY" ]; then
       export HTTPS_PROXY=$PROXY_ADDRESS
    fi
}

installDockerOnline() {
    compareDockerVersions "17.06.0" "$DOCKER_VERSION"
    if { [ "$LSB_DIST" = "rhel" ] || [ "$LSB_DIST" = "ol" ] ; } && [ "$COMPARE_DOCKER_VERSIONS_RESULT" -le "0" ]; then
        if yum list installed "container-selinux" >/dev/null 2>&1; then
            # container-selinux installed
            printf "Skipping install of container-selinux as a version of it was already present\n"
        else
            # Install container-selinux from official source, ignoring errors
            yum install -y -q container-selinux 2> /dev/null || true
            # verify installation success
            if yum list installed "container-selinux" >/dev/null 2>&1; then
                printf "{$GREEN}Installed container-selinux from existing sources{$NC}\n"
            else
                if [ "$DIST_VERSION" = "7.6" ]; then
                    # Install container-selinux from mirror.centos.org
                    yum install -y -q "http://mirror.centos.org/centos/7/extras/x86_64/Packages/container-selinux-2.99-1.el7_6.noarch.rpm" || \
                        yum install -y -q "http://mirror.centos.org/centos/7/extras/x86_64/Packages/container-selinux-2.95-2.el7_6.noarch.rpm"
                    if yum list installed "container-selinux" >/dev/null 2>&1; then
                        printf "${YELLOW}Installed package required by docker container-selinux from fallback source of mirror.centos.org${NC}\n"
                    else
                        printf "${RED}Failed to install container-selinux package, required by Docker CE. Please install the container-selinux package or Docker before running this installation script.${NC}\n"
                        exit 1
                    fi
                else
                    # Install container-selinux from mirror.centos.org
                    yum install -y -q "http://mirror.centos.org/centos/7/extras/x86_64/Packages/container-selinux-2.74-1.el7.noarch.rpm" || \
                        yum install -y -q "http://mirror.centos.org/centos/7/extras/x86_64/Packages/container-selinux-2.68-1.el7.noarch.rpm"
                    if yum list installed "container-selinux" >/dev/null 2>&1; then
                        printf "${YELLOW}Installed package required by docker container-selinux from fallback source of mirror.centos.org${NC}\n"
                    else
                        printf "${RED}Failed to install container-selinux package, required by Docker CE. Please install the container-selinux package or Docker before running this installation script.${NC}\n"
                        exit 1
                    fi
                fi
            fi
        fi
    fi

    _docker_install_url="https://get.replicated.com/docker-install.sh"
    curl "$_docker_install_url?docker_version=${1}&lsb_dist=${LSB_DIST}&dist_version=${DIST_VERSION_MAJOR}" > /tmp/docker_install.sh
    # When this script is piped into bash as stdin, apt-get will eat the remaining parts of this script,
    # preventing it from being executed.  So using /dev/null here to change stdin for the docker script.
    VERSION="${1}" sh /tmp/docker_install.sh < /dev/null

    printf "${GREEN}External script is finished${NC}\n"

    systemctl enable docker
    systemctl start docker

    # i guess the second arg means to skip this?
    if [ "$2" = "1" ]; then
        # set +e because df --output='fstype' doesn't exist on older versions of rhel and centos
        set +e
        _maybeRequireRhelDevicemapper
        set -e
    fi

    DID_INSTALL_DOCKER=1
}

installDockerOffline() {
    case "$LSB_DIST$DIST_VERSION" in
        ubuntu16.04)
            dpkg -i --force-depends-version $DIR/ubuntu-16.04/packages/docker/*.deb
            DID_INSTALL_DOCKER=1
            return
            ;;
        ubuntu18.04)
            dpkg -i --force-depends-version $DIR/ubuntu-18.04/packages/docker/*.deb
            DID_INSTALL_DOCKER=1
            return
            ;;
        rhel7.4|rhel7.5|rhel7.6|centos7.4|centos7.5|centos7.6)
            rpm --upgrade --force --nodeps $DIR/rhel-7/packages/k8s/*.rpm
            DID_INSTALL_DOCKER=1
            return
            ;;
        *)
   esac

   printf "Offline Docker install is not supported on ${LSB_DIST} ${DIST_MAJOR}"
   exit 1
}

_maybeRequireRhelDevicemapper() {
    # If the distribution is CentOS or RHEL and the filesystem is XFS, it is possible that docker has installed with overlay as the device driver
    # but the ftype!=1.
    # In that case we should change the storage driver to devicemapper, because while loopback-lvm is slow it is also more likely to work
    if { [ "$LSB_DIST" = "centos" ] || [ "$LSB_DIST" = "rhel" ] ; } && { df --output='fstype' | grep -q -e '^xfs$' || grep -q -e ' xfs ' /etc/fstab ; } ; then
        # If distribution is centos or rhel and filesystem is XFS

        # xfs (RHEL 7.2 and higher), but only with d_type=true enabled. Use xfs_info to verify that the ftype option is set to 1.
        # https://docs.docker.com/storage/storagedriver/overlayfs-driver/#prerequisites
        oIFS="$IFS"; IFS=.; set -- $DIST_VERSION; IFS="$oIFS";
        _dist_version_minor=$2
        if [ "$DIST_VERSION_MAJOR" -eq "7" ] && [ "$_dist_version_minor" -ge "2" ] && xfs_info / | grep -q -e 'ftype=1'; then
            return
        fi

        # Get kernel version (and extract major+minor version)
        kernelVersion="$(uname -r)"
        semverParse $kernelVersion

        if docker info | grep -q -e 'Storage Driver: overlay2\?' && { ! xfs_info / | grep -q -e 'ftype=1' || [ $major -lt 3 ] || { [ $major -eq 3 ] && [ $minor -lt 18 ]; }; }; then
            # If storage driver is overlay and (ftype!=1 OR kernel version less than 3.18)
            printf "${YELLOW}Changing docker storage driver to devicemapper."
            printf "Using overlay/overlay2 requires CentOS/RHEL 7.2 or higher and ftype=1 on xfs filesystems.\n"
            printf "It is recommended to configure devicemapper to use direct-lvm mode for production.${NC}\n"
            systemctl stop docker

            insertOrReplaceJsonParam /etc/docker/daemon.json storage-driver devicemapper

            systemctl start docker
        fi
    fi
}

checkDockerStorageDriver() {
    if [ "$BYPASS_STORAGEDRIVER_WARNINGS" = "1" ]; then
        return
    fi

    _driver=$(docker info 2>/dev/null | grep 'Storage Driver' | awk '{print $3}' | awk -F- '{print $1}')
    if [ "$_driver" = "devicemapper" ] && docker info 2>/dev/null | grep -Fqs 'Data loop file:' ; then
        printf "${RED}The running Docker daemon is configured to use the 'devicemapper' storage driver \
in loopback mode.\nThis is not recommended for production use. Please see to the following URL for more \
information.\n\nhttps://help.replicated.com/docs/kb/developer-resources/devicemapper-warning/.${NC}\n\n\
"
        # HARD_FAIL_ON_LOOPBACK
        if [ -n "$1" ]; then
            printf "${RED}Please configure a recommended storage driver and try again.${NC}\n\n"
            exit 1
        fi

        printf "Do you want to proceed anyway? "
        if ! confirmN; then
            exit 0
        fi
    fi
}

requireDockerProxy() {
    # NOTE: this does not take into account if no proxy changed
    _previous_proxy="$(docker info 2>/dev/null | grep -i 'Http Proxy:' | sed 's/Http Proxy: //I')"
    if [ "$PROXY_ADDRESS" = "$_previous_proxy" ]; then
        return
    fi

    _allow=n
    if [ "$DID_INSTALL_DOCKER" = "1" ]; then
        _allow=y
    else
        if [ -n "$_previous_proxy" ]; then
            printf "${YELLOW}It looks like Docker is set up with http proxy address $_previous_proxy.${NC}\n"
            printf "${YELLOW}This script will automatically reconfigure it now.${NC}\n"
        else
            printf "${YELLOW}It does not look like Docker is set up with http proxy enabled.${NC}\n"
            printf "${YELLOW}This script will automatically configure it now.${NC}\n"
        fi
        printf "${YELLOW}Do you want to allow this?${NC} "
        if confirmY; then
            _allow=y
        fi
    fi
    if [ "$_allow" = "y" ]; then
        configureDockerProxy
    else
        printf "${YELLOW}Do you want to proceed anyway?${NC} "
        if ! confirmN; then
            printf "${RED}Please manually configure your Docker daemon with environment HTTP_PROXY.${NC}\n" 1>&2
            exit 1
        fi
    fi
}

configureDockerProxy() {
	_docker_conf_file=/etc/systemd/system/docker.service.d/http-proxy.conf
	mkdir -p /etc/systemd/system/docker.service.d
	_configureDockerProxySystemd "$_docker_conf_file" "$PROXY_ADDRESS" "$NO_PROXY_ADDRESSES"
	RESTART_DOCKER=1
	DID_CONFIGURE_DOCKER_PROXY=1
}

#######################################
# Configures systemd docker to run with an http proxy.
# Globals:
#   None
# Arguments:
#   $1 - config file
#   $2 - proxy address
#   $3 - no proxy address
# Returns:
#   None
#######################################
_configureDockerProxySystemd() {
    if [ ! -e "$1" ]; then
        touch "$1" # create the file if it doesn't exist
    fi

    if [ ! -s "$1" ]; then # if empty
        echo "# Generated by replicated install script" >> "$1"
        echo "[Service]" >> "$1"
    fi
    if ! grep -q "^\[Service\] *$" "$1"; then
        # don't mess with this file in this case
        return
    fi
    if ! grep -q "^Environment=" "$1"; then
        echo "Environment=" >> "$1"
    fi

    sed -i'' -e "s/\"*HTTP_PROXY=[^[:blank:]]*//" "$1" # remove new no proxy address
    sed -i'' -e "s/\"*NO_PROXY=[^[:blank:]]*//" "$1" # remove old no proxy address
    sed -i'' -e "s/^\(Environment=\) */\1/" "$1" # remove space after equals sign
    sed -i'' -e "s/ $//" "$1" # remove trailing space
    sed -i'' -e "s#^\(Environment=.*$\)#\1 \"HTTP_PROXY=${2}\" \"NO_PROXY=${3}\"#" "$1"
}


# k8sVersion is an argument because this may be used to install step versions of K8s during an upgrade
# to the target version
installKubernetesComponents() {
    k8sVersion=$1

    logStep "Install kubelet, kubeadm, kubectl and cni binaries"

    if kubernetesHostCommandsOK; then
        logSuccess "Kubernetes components already installed"
        return
    fi

    case "$LSB_DIST$DIST_VERSION" in
        ubuntu16.04)
            if [ "$AIRGAP" != "1" ] && [ -n "$INSTALL_URL" ]; then
                curl -O "$INSTALL_URL/dist/k8s-ubuntu-1604.tar.gz"
                mkdir -p $DIR/ubuntu-16.04/packages/k8s
                tar xf k8s-ubuntu-1604.tar.gz -C $DIR/ubuntu-18.04/packages/k8s
            fi
            export DEBIAN_FRONTEND=noninteractive
            dpkg -i --force-depends-version $DIR/ubuntu-16.04/packages/k8s/*.deb
            ;;
        ubuntu18.04)
            if [ "$AIRGAP" != "1" ] && [ -n "$INSTALL_URL" ]; then
                curl -O "$INSTALL_URL/dist/k8s-ubuntu-1804.tar.gz"
                mkdir -p $DIR/ubuntu-18.04/packages/k8s
                tar xf k8s-ubuntu-1804.tar.gz -C $DIR/ubuntu-18.04/packages/k8s
            fi

            export DEBIAN_FRONTEND=noninteractive
            dpkg -i --force-depends-version $DIR/ubuntu-18.04/packages/k8s/*.deb
            ;;

        centos7.4|centos7.5|centos7.6|rhel7.4|rhel7.5|rhel7.6)
            # This needs to be run on Linux 3.x nodes for Rook
            modprobe rbd
            echo 'rbd' > /etc/modules-load.d/replicated-rook.conf

            echo "net.bridge.bridge-nf-call-ip6tables = 1" > /etc/sysctl.d/k8s.conf
            echo "net.bridge.bridge-nf-call-iptables = 1" >> /etc/sysctl.d/k8s.conf
            echo "net.ipv4.conf.all.forwarding = 1" >> /etc/sysctl.d/k8s.conf

            sysctl --system

            if [ "$AIRGAP" != "1" ] && [ -n "$INSTALL_URL" ]; then
                curl -O "$INSTALL_URL/dist/k8s-rhel-7.tar.gz"
                mkdir -p $DIR/rhel-7/packages/k8s
                tar xf k8s-rhel-7.tar.gz -C $DIR/rhel-7/packages/k8s
            fi
            rpm --upgrade --force --nodeps $DIR/rhel-7/packages/k8s/*.rpm
            service docker restart
            ;;

        *)
            bail "Kubernetes install is not supported on ${LSB_DIST} ${DIST_VERSION}"
            ;;
    esac

    rm -rf archives

    if [ "$CLUSTER_DNS" != "$DEFAULT_CLUSTER_DNS" ]; then
        sed -i "s/$DEFAULT_CLUSTER_DNS/$CLUSTER_DNS/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    fi
    systemctl enable kubelet && systemctl start kubelet

    logSuccess "Kubernetes components installed"
}

kubernetesHostCommandsOK() {
    if ! commandExists kubelet; then
        printf "kubelet command missing - will install host components\n"
        return 1
    fi
    if ! commandExists kubeadm; then
        printf "kubeadm command missing - will install host components\n"
        return 1
    fi
    if ! commandExists kubectl; then
        printf "kubectl command missing - will install host components\n"
        return 1
    fi

    return 0
}

lockPackageVersion() {
    case $LSB_DIST in
        rhel|centos)
            yum install -y yum-plugin-versionlock
            yum versionlock ${1}-*
            ;;
        ubuntu)
            apt-mark hold $1
            ;;
    esac
}

airgapLoadKubernetesImages() {
    docker load < $DIR/k8s-images.tar
    docker run \
        -v /var/run/docker.sock:/var/run/docker.sock \
	    "kurl/k8s-images:${KUBERNETES_VERSION}"

    (
        set -x
        docker tag $HYPERKUBE_IMAGE_ID k8s.gcr.io/hyperkube:v${KUBERNETES_VERSION}
        docker tag $ETCD_IMAGE_ID k8s.gcr.io/etcd:${ETCD_VERSION}
        docker tag $PAUSE_IMAGE_ID k8s.gcr.io/pause:${PAUSE_VERSION}
        docker tag $COREDNS_IMAGE_ID k8s.gcr.io/coredns:${COREDNS_VERSION}
        docker tag $WEAVE_KUBE_IMAGE_ID docker.io/weaveworks/weave-kube:${WEAVE_VERSION}
        docker tag $WEAVE_NPC_IMAGE_ID docker.io/weaveworks/weave-npc:${WEAVE_VERSION}
        docker tag $WEAVE_EXEC_IMAGE_ID docker.io/weaveworks/weaveexec:${WEAVE_VERSION}
        docker tag $ENVOY_IMAGE_ID docker.io/envoyproxy/envoy-alpine:v${ENVOY_VERSION}
        docker tag $CONTOUR_IMAGE_ID gcr.io/heptio-images/contour:v${CONTOUR_VERSION}
        docker tag $ROOK_IMAGE_ID docker.io/rook/ceph:v${ROOK_VERSION}
        docker tag $CEPH_IMAGE_ID docker.io/ceph/ceph:v${CEPH_VERSION}
    )
}
