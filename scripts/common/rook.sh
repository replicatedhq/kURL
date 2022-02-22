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

function prometheus_pods_gone() {
    if kubectl -n monitoring get pods -l app=prometheus 2>&1 | grep 'prometheus' &>/dev/null ; then
        if kubectl -n monitoring get pods -l app.kubernetes.io/name=prometheus 2>&1 | grep 'prometheus' &>/dev/null ; then # the labels changed with prometheus 0.53+
            return 1
        fi
    fi
    return 0
}

function ekco_pods_gone() {
    if kubectl -n kurl get pods -l app=ekc-operator 2>&1 | grep 'ekc' &>/dev/null ; then
        return 1
    fi
    return 0
}

function remove_rook_ceph() {
    # make sure there aren't any PVs using rook before deleting it
    all_pv_drivers="$(kubectl get pv -o=jsonpath='{.items[*].spec.csi.driver}')"
    if echo "$all_pv_drivers" | grep "rook" &>/dev/null ; then
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
        echo "Waiting for ekco pods to be removed"
        spinner_until 120 ekco_pods_gone
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
        kubectl -n kurl get configmap ekco-config -o yaml | \
            sed --expression='s/maintain_rook_storage_nodes:[ ]*true/maintain_rook_storage_nodes: false/g' | \
            kubectl -n kurl apply -f - 
        kubectl -n kurl scale deploy ekc-operator --replicas=1
    fi

    # print success message
    printf "${GREEN}Removed rook-ceph successfully!\n${NC}"
    printf "Data within /var/lib/rook, /opt/replicated/rook and any bound disks has not been freed.\n"
}

# scale down prometheus, move all 'rook-ceph' PVCs to 'longhorn', scale up prometheus
function rook_ceph_to_longhorn() {
    report_addon_start "rook-ceph-to-longhorn" "v1"

    # set prometheus scale if it exists
    if kubectl get namespace monitoring &>/dev/null; then
        if kubectl get prometheus -n monitoring k8s &>/dev/null; then
            # before scaling down prometheus, scale down ekco as it will otherwise restore the prometheus scale
            if kubernetes_resource_exists kurl deployment ekc-operator; then
                kubectl -n kurl scale deploy ekc-operator --replicas=0
                echo "Waiting for ekco pods to be removed"
                spinner_until 120 ekco_pods_gone
            fi

            kubectl patch prometheus -n monitoring  k8s --type='json' --patch '[{"op": "replace", "path": "/spec/replicas", value: 0}]'
            echo "Waiting for prometheus pods to be removed"
            spinner_until 120 prometheus_pods_gone
        fi
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

    # reset prometheus (and ekco) scale
    if kubectl get namespace monitoring &>/dev/null; then
        if kubectl get prometheus -n monitoring k8s &>/dev/null; then
            if kubernetes_resource_exists kurl deployment ekc-operator; then
                kubectl -n kurl scale deploy ekc-operator --replicas=1
            fi

            kubectl patch prometheus -n monitoring  k8s --type='json' --patch '[{"op": "replace", "path": "/spec/replicas", value: 2}]'
        fi
    fi

    # print success message
    printf "${GREEN}Migration from rook-ceph to longhorn completed successfully!\n${NC}"
    report_addon_success "rook-ceph-to-longhorn" "v1"
}

# if PVCs and object store data have both been migrated from rook-ceph and rook-ceph is no longer specified in the kURL spec, remove rook-ceph
function maybe_cleanup_rook() {
    if [ -z "$ROOK_VERSION" ]; then
        if [ "$DID_MIGRATE_ROOK_PVCS" == "1" ] && [ "$DID_MIGRATE_ROOK_OBJECT_STORE" == "1" ]; then
            report_addon_start "rook-ceph-removal" "v1"
            remove_rook_ceph
            report_addon_success "rook-ceph-removal" "v1"
        fi
    fi
}
