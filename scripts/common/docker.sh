
function change_cgroup_driver_to_systemd() {
    # Docker uses cgroupfs by defualt to manage cgroup. On distributions using systemd,
    # i.e. RHEL and Ubuntu, this causes issues because there are now 2 seperate ways
    # to manage resources. For more info see the link below.
    # https://github.com/kubernetes/kubeadm/issues/1394#issuecomment-462878219

    if [ -f /var/lib/kubelet/kubeadm-flags.env ] || [ -f /etc/docker/daemon.json ]; then
    	return
    fi

    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
    "exec-opts": ["native.cgroupdriver=systemd"]
}
EOF

    mkdir -p /etc/systemd/system/docker.service.d
}

function install_docker() {
    if [ "$SKIP_DOCKER_INSTALL" != "1" ]; then
        if [ -z "$DOCKER_VERSION" ]; then
            printf "${RED}The installer did not specify a version of Docker to include, but is required by all kURL installation scripts currently. The latest supported version of Docker will be installed.${NC}\n"
        fi
        change_cgroup_driver_to_systemd
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

    # DONE QA preserve docker config
    if [ -z "$PRESERVE_DOCKER_CONFIG" ] && [ -n "$PROXY_ADDRESS" ]; then
        docker_configure_proxy
        local dockerProxy=$(docker info 2>/dev/null | grep -i "HTTP Proxy:")
        if ! echo "$dockerProxy" | grep -q "$PROXY_ADDRESS"; then
            bail "Docker proxy configuration failed"
        fi
    fi
}

function restart_docker() {
    systemctl daemon-reload
    systemctl restart docker
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
                    yum install -y -q "http://mirror.centos.org/centos/7/extras/x86_64/Packages/container-selinux-2.107-1.el7_6.noarch.rpm"
                    if yum list installed "container-selinux" >/dev/null 2>&1; then
                        printf "${YELLOW}Installed package required by docker container-selinux from fallback source of mirror.centos.org${NC}\n"
                    else
                        printf "${RED}Failed to install container-selinux package, required by Docker CE. Please install the container-selinux package or Docker before running this installation script.${NC}\n"
                        exit 1
                    fi
                else
                    # Install container-selinux from mirror.centos.org
                    yum install -y -q "http://mirror.centos.org/centos/7/extras/x86_64/Packages/container-selinux-2.107-3.el7.noarch.rpm"
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
   case "$LSB_DIST" in
        ubuntu)
            export DEBIAN_FRONTEND=noninteractive
            dpkg --install --force-depends-version $DIR/packages/docker/${DOCKER_VERSION}/ubuntu-${DIST_VERSION}/*.deb
            DID_INSTALL_DOCKER=1
            return 0
            ;;

        centos|rhel)
            rpm --upgrade --force --nodeps $DIR/packages/docker/${DOCKER_VERSION}/rhel-7/*.rpm
            DID_INSTALL_DOCKER=1
            return 0
            ;;
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

# DONE QA no restart docker if no change
# DONE QA change if already exists
docker_configure_proxy() {
    # NOTE: this does not take into account if no proxy changed
    local previous_proxy=$(docker info 2>/dev/null | grep -i 'Http Proxy:' | awk '{ print $NF }')
    local previous_no_proxy=$(docker info 2>/dev/null | grep -i 'No Proxy:' | awk '{ print $NF }')
    if [ "$PROXY_ADDRESS" = "$previous_proxy" ] && [ "$NO_PROXY_ADDRESSES" = "$previous_no_proxy" ]; then
        return
    fi

	mkdir -p /etc/systemd/system/docker.service.d
    local file=/etc/systemd/system/docker.service.d/http-proxy.conf

    echo "# Generated by kURL" > $file
    echo "[Service]" >> $file

    if echo "$PROXY_ADDRESS" | grep -q "^https"; then
        echo "Environment=\"HTTPS_PROXY=${PROXY_ADDRESS}\" \"NO_PROXY=${NO_PROXY_ADDRESSES}\"" >> $file
    else
        echo "Environment=\"HTTP_PROXY=${PROXY_ADDRESS}\" \"NO_PROXY=${NO_PROXY_ADDRESSES}\"" >> $file
    fi

    restart_docker
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
