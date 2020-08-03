
function containerd() {
    containerd_install
}

function containerd_join() {
    containerd_install
}

function containerd_install() {
    local src="$DIR/addons/containerd/1.2.13"

    containerd_binaries "$src"
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
    systemctl enable ekco-reboot.service
    systemctl start ekco-reboot.service
}
