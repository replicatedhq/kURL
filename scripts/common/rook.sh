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

function is_rook_1() {
    kubectl -n rook-ceph get cephblockpools replicapool &>/dev/null
}

function rook_ceph_osd_pods_gone() {
    if kubectl -n rook-ceph get pods -l app=rook-ceph-osd 2>&1 | grep 'rook-ceph-osd' &>/dev/null ; then
        return 1
    fi
    return 0
}

function remove_rook_ceph() {
    # make sure there aren't any PVs using rook before deleting it
    rook_pvs="$(kubectl get pv -o=jsonpath='{.items[*].spec.csi.driver}' | grep rook)"
    if [ -n "$rook_pvs" ]; then
        # do stuff
        printf "${RED}"
        printf "ERROR: \n"
        printf "There are still PVs using rook-ceph.\n"
        printf "Remove these PVs before continuing.\n"
        printf "${NC}"
        exit 1
    fi

    # scale ekco to 0 replicas if it exists
    if kubernetes_resource_exists kurl deployment ekc-operator; then
        kubectl -n kurl scale deploy ekc-operator --replicas=0
    fi

    # remove all rook-ceph CR objects
    printf "Removing rook-ceph custom resource objects - this may take some time:\n"
    kubectl delete cephcluster -n rook-ceph rook-ceph # deleting this first frees up resources
    kubectl get crd | grep 'ceph.rook.io' | awk '{ print $1 }' | xargs -I'{}' kubectl -n rook-ceph delete '{}' --all
    kubectl delete volumes.rook.io --all

    # wait for rook-ceph-osd pods to disappear
    echo "Waiting for rook-ceph OSD pods to be removed"
    spinner_until 120 rook_ceph_osd_pods_gone

    # delete rook-ceph CRDs
    printf "Removing rook-ceph custom resources:\n"
    kubectl get crd | grep 'ceph.rook.io' | awk '{ print $1 }' | xargs -I'{}' kubectl delete crd '{}'
    kubectl delete crd volumes.rook.io

    # delete rook-ceph ns
    kubectl delete ns rook-ceph

    # delete rook-ceph storageclass(es)
    printf "Removing rook-ceph StorageClasses"
    kubectl get storageclass | grep rook | awk '{ print $1 }' | xargs -I'{}' kubectl delete storageclass '{}'

    # scale ekco back to 1 replicas if it exists
    if kubernetes_resource_exists kurl deployment ekc-operator; then
        kubectl -n kurl scale deploy ekc-operator --replicas=1
    fi

    # print success message
    printf "${GREEN}Removed rook-ceph successfully!\n${NC}"
    printf "Data within /var/lib/rook, /opt/replicated/rook and any bound disks has not been freed.\n"
}

# scale down prometheus, move all 'rook-ceph' PVCs to 'longhorn', scale up prometheus
function rook_ceph_to_longhorn() {
    # set prometheus scale if it exists
    if kubectl get namespace monitoring &>/dev/null; then
        kubectl patch prometheus -n monitoring  k8s --type='json' --patch '[{"op": "replace", "path": "/spec/replicas", value: 0}]'
    fi

    # get the list of StorageClasses that use rook-ceph
    rook_scs=$(kubectl get storageclass | grep rook | grep -v '(default)' | awk '{ print $1}') # any non-default rook StorageClasses
    rook_default_sc=$(kubectl get storageclass | grep rook | grep '(default)' | awk '{ print $1}') # any default rook StorageClasses

    for rook_sc in $rook_scs
    do
        # run the migration (without setting defaults)
        $BIN_PVMIGRATE --source-sc "$rook_sc" --dest-sc longhorn --rsync-image "$KURL_UTIL_IMAGE"
    done

    for rook_sc in $rook_default_sc
    do
        # run the migration (setting defaults)
        $BIN_PVMIGRATE --source-sc "$rook_sc" --dest-sc longhorn --rsync-image "$KURL_UTIL_IMAGE" --set-defaults
    done

    # reset prometheus scale
    if kubectl get namespace monitoring &>/dev/null; then
        kubectl patch prometheus -n monitoring  k8s --type='json' --patch '[{"op": "replace", "path": "/spec/replicas", value: 2}]'
    fi

    # print success message
    printf "${GREEN}Migration from rook-ceph to longhorn completed successfully!\n${NC}"
}
