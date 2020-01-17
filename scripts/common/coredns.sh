function disable_coredns() {
    kubectl -n kube-system scale deployment coredns --replicas=0
}

function enable_coredns() {
    kubectl -n kube-system scale deployment coredns --replicas=2
}
