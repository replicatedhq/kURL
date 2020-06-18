function containerd_get_host_packages_online() {
    local version="$1"

    if [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        curl -sSLO "$DIST_URL/containerd-${version}.tar.gz"
        tar xf containerd-${version}.tar.gz
        rm containerd-${version}.tar.gz
    fi
}

function configure_containerd() {
      mkdir -p /etc/containerd
      containerd config default > /etc/containerd/config.toml

      sed -i 's/systemd_cgroup = false/systemd_cgroup = true/' /etc/containerd/config.toml

      systemctl restart containerd
}


function install_containerd() {
   if [ "$SKIP_CONTAINERD_INSTALL" != "1" ]; then

     containerd_get_host_packages_online "$CONTAINERD_VERSION"

     case "$LSB_DIST$DIST_VERSION" in
         ubuntu16.04)
            export DEBIAN_FRONTEND=noninteractive
            dpkg --install --force-depends-version $DIR/packages/containerd/$CONTAINERD_VERSION/ubuntu-${DIST_VERSION}/*.deb
            ;;
         ubuntu18.04)
            export DEBIAN_FRONTEND=noninteractive
            dpkg --install --force-depends-version $DIR/packages/containerd/$CONTAINERD_VERSION/ubuntu-${DIST_VERSION}/*.deb
            ;;
         rhel7.7|rhel7.8|rhel8.0|rhel8.1|centos7.7|centos7.8|centos8.0|centos8.1|amzn2)
            rpm --upgrade --force --nodeps $DIR/packages/containerd/$CONTAINERD_VERSION/rhel-7/*.rpm
            ;;
         *)
            bail "kURL does not support containerd on ${LSB_DIST} ${DIST_VERSION}, please use docker instead"
            ;;
      esac

      configure_containerd
   fi
}
