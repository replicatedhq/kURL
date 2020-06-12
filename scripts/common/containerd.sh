function install_containerd() {
   if [ "$SKIP_CONTAINERD_INSTALL" != "1" ]; then
     case "$LSB_DIST$DIST_VERSION" in
         # ubuntu16.04)
         #    export DEBIAN_FRONTEND=noninteractive
         #    dpkg --install --force-depends-version $DIR/packages/containerd/1.2.6/ubuntu-${DIST_VERSION}/*.deb
         #    ;;
         # ubuntu18.04)
         #    export DEBIAN_FRONTEND=noninteractive
         #    dpkg --install --force-depends-version $DIR/packages/containerd/1.3.3/ubuntu-${DIST_VERSION}/*.deb
         #    ;;
         rhel7.7|rhel7.8|rhel8.0|rhel8.1|centos7.7|centos7.8|centos8.0|centos8.1|amzn2)
            rpm --upgrade --force --nodeps $DIR/packages/containerd/1.2.13/rhel-7/*.rpm
            ;;
         *)
            bail "kURL does not support containerd on ${LSB_DIST} ${DIST_VERSION}, please use docker instead"
            ;;
      esac

      mkdir -p /etc/containerd
      containerd config default > /etc/containerd/config.toml

      sed -i 's/systemd_cgroup = false/systemd_cgroup = true/' /etc/containerd/config.toml

      systemctl restart containerd
   fi
}
