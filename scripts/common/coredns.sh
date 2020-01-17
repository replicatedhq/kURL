function disable_coredns() {
    echo "------------------------scaling coredns down from 2 > 0"
    kubectl -n kube-system scale deployment coredns --replicas=0
}

function enable_coredns() {
    echo "------------------------scaling coredns up from 0 > 2"
    kubectl -n kube-system scale deployment coredns --replicas=2
}
