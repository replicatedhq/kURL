

function containerd_install() {
    local src="$DIR/addons/containerd/1.3.7"

    if [ "$SKIP_CONTAINERD_INSTALL" = "1" ]; then
        return 0
    fi

    containerd_binaries "$src"
    containerd_configure
    containerd_service "$src"
}

function containerd_binaries() {
    local src="$1"

    if [ ! -f "$src/assets/containerd.tar.gz" ] && [ "$AIRGAP" != "1" ]; then
        mkdir -p "$src/assets"
        curl -L https://github.com/containerd/containerd/releases/download/v1.3.7/containerd-1.3.7-linux-amd64.tar.gz > "$src/assets/containerd.tar.gz"
    fi
    tar xzf "$src/assets/containerd.tar.gz" -C /usr

    if [ ! -f "$src/assets/runc" ] && [ "$AIRGAP" != "1" ]; then
		curl -L https://github.com/opencontainers/runc/releases/download/v1.0.0-rc91/runc.amd64 > "$src/assets/runc"
	fi
    chmod 0755 "$src/assets/runc"
    mv "$src/assets/runc" /usr/bin
}

function containerd_service() {
    local src="$1"

    local systemdVersion=$(systemctl --version | head -1 | awk '{ print $NF }')
    if [ $systemdVersion -ge 226 ]; then
        cp "$src/containerd.service" /etc/systemd/system/containerd.service
    else
        cat "$src/containerd.service" | sed '/TasksMax/s//# &/' > /etc/systemd/system/containerd.service
    fi

    systemctl daemon-reload
    systemctl enable containerd.service
    systemctl start containerd.service
}

function containerd_configure() {
    if [ -s "/etc/containerd/config.toml" ]; then
        return 0
    fi

    sleep 1

    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml

    sed -i '/systemd_cgroup/d' /etc/containerd/config.toml
    cat >> /etc/containerd/config.toml <<EOF
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
  systemd_cgroup = true
EOF

    # Always set for joining nodes since it's passed as a flag in the generated join script, but not
    # usually set for the initial install
    if [ -n "$DOCKER_REGISTRY_IP" ]; then
        containerd_configure_registry "$DOCKER_REGISTRY_IP"
    fi
        
}

function containerd_registry_init() {
    if [ -z "$REGISTRY_VERSION" ]; then
        return 0
    fi

    local registryIP=$(kubectl -n kurl get service registry -o=jsonpath='{@.spec.clusterIP}' 2>/dev/null || true)
    if [ -z "$registryIP" ]; then
        kubectl apply -f "$DIR/addons/registry/2.7.1/namespace.yaml"
        kubectl -n kurl apply -f "$DIR/addons/registry/2.7.1/service.yaml"
        registryIP=$(kubectl -n kurl get service registry -o=jsonpath='{@.spec.clusterIP}')
    fi

    containerd_configure_registry "$registryIP"
    systemctl restart containerd
}

function containerd_configure_registry() {
    local registryIP="$1"

    if grep -q "plugins.\"io.containerd.grpc.v1.cri\".registry.configs.\"${registryIP}\".tls" /etc/containerd/config.toml; then
        echo "Registry ${registryIP} TLS already configured for containerd"
        return 0
    fi

    cat >> /etc/containerd/config.toml <<EOF
[plugins."io.containerd.grpc.v1.cri".registry.configs."${registryIP}".tls]
  ca_file = "/etc/kubernetes/pki/ca.crt"
EOF
}
