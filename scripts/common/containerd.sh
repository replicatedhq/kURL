function containerd_get_host_packages_online() {
    local version="$1"

    if [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        curl -sSLO "$DIST_URL/containerd-${version}.tar.gz"
        tar xf containerd-${version}.tar.gz
        rm containerd-${version}.tar.gz
    fi
}

function configure_containerd() {
      sleep 1

      mkdir -p /etc/containerd
      containerd config default > /etc/containerd/config.toml

      sed -i 's/systemd_cgroup = false/systemd_cgroup = true/' /etc/containerd/config.toml

      systemctl restart containerd
      systemctl enable containerd
}


function install_containerd() {
   if [ "$SKIP_CONTAINERD_INSTALL" != "1" ]; then

     containerd_get_host_packages_online "$CONTAINERD_VERSION"

     case "$LSB_DIST$DIST_VERSION" in
         ubuntu16.04|ubuntu18.04|ubuntu20.04)
            export DEBIAN_FRONTEND=noninteractive
            dpkg --install --force-depends-version $DIR/packages/containerd/$CONTAINERD_VERSION/ubuntu-${DIST_VERSION}/*.deb
            ;;
         rhel7.7|rhel7.8|rhel8.0|rhel8.1|centos7.7|centos7.8|centos8.0|centos8.1|centos8.2|amzn2)
            rpm --upgrade --force --nodeps $DIR/packages/containerd/$CONTAINERD_VERSION/rhel-7/*.rpm
            ;;
         *)
            bail "kURL does not support containerd on ${LSB_DIST} ${DIST_VERSION}, please use docker instead"
            ;;
      esac

      configure_containerd
   fi
}

function add_registry_to_containerd_config() {
   local docker_registry_ip="$1"

#    This function will change the first configuration to the second in /etc/containerd/config.toml

#    [plugins.cri.registry]
#      [plugins.cri.registry.mirrors]
#        [plugins.cri.registry.mirrors."docker.io"]
#          endpoint = ["https://registry-1.docker.io"]

#    [plugins.cri.registry]
#      [plugins.cri.registry.mirrors]
#        [plugins.cri.registry.mirrors."docker.io"]
#          endpoint = ["https://registry-1.docker.io"]
#        [plugins.cri.registry.mirrors."registry.kurl.svc.cluster.local"]
#          endpoint = ["$SOME_IP:443"]
#      [plugins.cri.registry.configs]
#        [plugins.cri.registry.configs."registry.kurl.svc.cluster.local".tls]
#          ca_file = "/etc/kubernetes/pki/ca.crt"

   if ! grep -q "ca_file" /etc/containerd/config.toml; then
      sed -i "/registry-1/a \        [plugins.cri.registry.mirrors."\""registry.kurl.svc.cluster.local""\"]\n          endpoint = [""\"$1:443""\"]\n      [plugins.cri.registry.configs]\n        [plugins.cri.registry.configs."\""registry.kurl.svc.cluster.local""\".tls]\n          ca_file = "\""/etc/kubernetes/pki/ca.crt"\""" /etc/containerd/config.toml
   fi

   systemctl restart containerd
}

function containerd_registry_init() {
   if [ -n "$CONTAINERD_VERSION" ] && [ -n "$REGISTRY_VERSION" ]; then
       if ! kubectl -n kurl get service registry -o=jsonpath='{@.spec.clusterIP}'; then
        kubectl apply -f "$DIR/addons/registry/2.7.1/namespace.yaml"
        kubectl -n kurl apply -f "$DIR/addons/registry/2.7.1/service.yaml"
        DOCKER_REGISTRY_IP=$(kubectl -n kurl get service registry -o=jsonpath='{@.spec.clusterIP}')

        add_registry_to_containerd_config "$DOCKER_REGISTRY_IP"
       fi
   fi
}
