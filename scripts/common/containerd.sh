function install_containerd() {
    apt-get update && apt-get install -y apt-transport-https ca-certificates curl software-properties-common

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -

    add-apt-repository \
        "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) \
        stable"

    apt-get update && apt-get install -y containerd.io

    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml

    sed -i 's/systemd_cgroup = false/systemd_cgroup = true/' /etc/containerd/config.toml

    systemctl restart containerd
}
