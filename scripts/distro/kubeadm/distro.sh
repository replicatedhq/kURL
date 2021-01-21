
function kubeadm_discover_private_ip() {
    local private_address

    private_address="$(cat /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null | grep advertise-address | awk -F'=' '{ print $2 }')"

    # This is needed on k8s 1.18.x as $PRIVATE_ADDRESS is found to have a newline
    echo "${private_address}" | tr -d '\n'
}

function kubeadm_get_kubeconfig() {
    echo "/etc/kubernetes/admin.conf"
}

function kubeadm_get_containerd_sock() {
    echo "/run/containerd/containerd.sock"
}

function kubeadm_get_client_kube_apiserver_crt() {
    echo "/etc/kubernetes/pki/apiserver-kubelet-client.crt"
}

function kubeadm_get_client_kube_apiserver_key() {
    echo "/etc/kubernetes/pki/apiserver-kubelet-client.key"
}

function kubeadm_get_server_ca() {
    echo "/etc/kubernetes/pki/ca.crt"
}
