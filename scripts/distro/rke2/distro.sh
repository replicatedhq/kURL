
function rke2_discover_private_ip() {
    echo "$(cat /var/lib/rancher/rke2/agent/pod-manifests/etcd.yaml | grep initial-cluster | grep -o "${HOSTNAME}-[a-z0-9]*=https*://[^\",]*" | sed -n -e 's/.*https*:\/\/\(.*\):.*/\1/p')"
}

function rke2_get_kubeconfig() {
    echo "/etc/rancher/rke2/rke2.yaml"
}

function rke2_get_containerd_sock() {
    echo "/run/k3s/containerd/containerd.sock"
}

function rke2_get_client_kube_apiserver_crt() {
    echo "/var/lib/rancher/rke2/server/tls/client-kube-apiserver.crt"
}

function rke2_get_client_kube_apiserver_key() {
    echo "/var/lib/rancher/rke2/server/tls/client-kube-apiserver.key"
}

function rke2_get_server_ca() {
    echo "/var/lib/rancher/rke2/server/tls/server-ca.crt"
}
