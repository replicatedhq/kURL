PV_BASE_PATH=/opt/replicated/rook

function disable_rook_ceph_operator() {
    if ! is_rook_1; then
        return 0
    fi

    kubectl -n rook-ceph scale deployment rook-ceph-operator --replicas=0
}

function enable_rook_ceph_operator() {
    if ! is_rook_1; then
        return 0
    fi

    kubectl -n rook-ceph scale deployment rook-ceph-operator --replicas=1
}

function if_rook_1() {
    kubectl -n rook-ceph get cephblockpools replicapool &>/dev/null
}

