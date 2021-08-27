

function katacontainers() {
    local src="$DIR/addons/katacontainers/1.9.2"
    local dst="$DIR/kustomize/katacontainers"

    use_containerd

    cp "$src/kustomization.yaml" "$dst/"
}

function use_containerd() {
  mkdir -p  /etc/systemd/system/kubelet.service.d/
  cat << EOF | sudo tee  /etc/systemd/system/kubelet.service.d/0-containerd.conf
[Service]
Environment="KUBELET_EXTRA_ARGS=--container-runtime=remote --runtime-request-timeout=15m --container-runtime-endpoint=unix:///run/containerd/containerd.sock"
EOF

  systemctl daemon-reload

  systemctl restart containerd
  iptables -P FORWARD ACCEPT

}
