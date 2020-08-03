

function containerd_install() {
    local src="$DIR/addons/containerd/1.2.13"

    if [ "$SKIP_CONTAINERD_INSTALL" = "1" ]; then
        return 0
    fi

    containerd_binaries "$src"
    containerd_configure
    containerd_registry
    containerd_service "$src"
}

function containerd_binaries() {
    local src="$1"

    if [ ! -f "$src/assets/containerd.tar.gz" ] && [ "$AIRGAP" != "1" ]; then
        mkdir -p "$src/assets"
        curl -L "https://github.com/containerd/containerd/releases/download/v1.2.13/containerd-1.2.13-linux-amd64.tar.gz" > "$src/assets/containerd.tar.gz"
    fi

    tar xzf "$src/assets/containerd.tar.gz" -C /usr/local
}

function containerd_service() {
    local src="$1"

    local systemdVersion=$(systemctl --version | head -1 | awk '{ print $NF }')
    if [ $systemdVersion -ge 226 ]; then
        cp "$src/containerd.service" /etc/systemd/service/containerd.service
    else
        cat "$src/containerd.service" | sed '/TasksMax/s//# &/' > /etc/systemd/service/container.service
    fi

    systemctl daemon-reload
    systemctl enable containerd.service
    systemctl start containerd.service
}

function containerd_configure() {
    if [ -f "/etc/containerd/config.toml" ]; then
        return 0
    fi

    sleep 1

    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml

    sed -i 's/systemd_cgroup = false/systemd_cgroup = true/' /etc/containerd/config.toml

    systemctl restart containerd
    systemctl enable containerd
}

function containerd_registry() {
    if [ -z "$REGISTRY_VERSION" ]; then
        return 0
    fi

    local registryIP=$(kubectl -n kurl get service registry -o=jsonpath='{@.spec.clusterIP}' 2>/dev/null || true)
    if [ -z "$registryIP" ]; then
        kubectl apply -f "$DIR/addons/registry/2.7.1/namespace.yaml"
        kubectl -n kurl apply -f "$DIR/addons/registry/2.7.1/service.yaml"
        registryIP=$(kubectl -n kurl get service registry -o=jsonpath='{@.spec.clusterIP}')
    fi

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
