
function containerd_install() {
    local src="$DIR/addons/containerd/1.2.13"

    if [ "$SKIP_CONTAINERD_INSTALL" = "1" ]; then
        return 0
    fi

    containerd_binaries "$src"
    containerd_configure
    containerd_service "$src"
    load_images $src/images
}

function containerd_binaries() {
    local src="$1"

    if [ ! -f "$src/assets/containerd.tar.gz" ] && [ "$AIRGAP" != "1" ]; then
        mkdir -p "$src/assets"
        curl -L https://github.com/containerd/containerd/releases/download/v1.2.13/containerd-1.2.13.linux-amd64.tar.gz > "$src/assets/containerd.tar.gz"
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

    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml

    sed -i 's/systemd_cgroup = false/systemd_cgroup = true/' /etc/containerd/config.toml
    sed -i 's/level = ""/level = "warn"/' /etc/containerd/config.toml
}
