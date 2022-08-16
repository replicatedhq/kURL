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
        return 1
    fi
    if kubectl -n monitoring get pods -l app.kubernetes.io/name=prometheus 2>&1 | grep 'prometheus' &>/dev/null ; then # the labels changed with prometheus 0.53+
        return 1
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

    # patch ceph so that it does not consume new devices that longhorn creates
    echo "Patching CephCluster storage.useAllDevices=false"
    kubectl -n rook-ceph patch cephcluster rook-ceph --type json --patch '[{"op": "replace", "path": "/spec/storage/useAllDevices", value: false}]'
    sleep 1
    echo "Waiting for CephCluster to update"
    spinner_until 300 rook_osd_phase_ready || true # don't fail

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

function rook_osd_phase_ready() {
    [ "$(kubectl -n rook-ceph get cephcluster rook-ceph --template '{{.status.phase}}')" = 'Ready' ]
}

function current_rook_version() {
    kubectl -n rook-ceph get deploy rook-ceph-operator -oyaml 2>/dev/null \
        | grep ' image: ' \
        | awk -F':' 'NR==1 { print $3 }' \
        | sed 's/v\([^-]*\).*/\1/'
}

# checks if rook should be upgraded before upgrading k8s. If it should, reports that as an addon, and starts the upgrade process.
function report_upgrade_rook() {
    if should_upgrade_rook_10_to_14; then
        ROOK_10_TO_14_VERSION="v1.0.0" # if you change this code, change the version
        report_addon_start "rook_10_to_14" "$ROOK_10_TO_14_VERSION"
        export REPORTING_CONTEXT_INFO="rook_10_to_14 $ROOK_10_TO_14_VERSION"
        rook_10_to_14
        export REPORTING_CONTEXT_INFO=""
        report_addon_success "rook_10_to_14" "$ROOK_10_TO_14_VERSION"
    fi
}

# checks the currently installed rook version and the desired rook version
# if the current version is 1.0-3.x and the desired version is 1.4.9+, returns true
function should_upgrade_rook_10_to_14() {
    # rook is not currently installed, so no upgrade
    if ! is_rook_1 ; then
        return 1
    fi

    # rook is not requested to be installed, so no upgrade
    if [ -z "${ROOK_VERSION}" ]; then
        return 1
    fi

    current_version="$(current_rook_version)"
    semverParse "${current_version}"
    current_rook_version_major="${major}"
    current_rook_version_minor="${minor}"

    semverParse "${ROOK_VERSION}"
    next_rook_version_major="${major}"
    next_rook_version_minor="${minor}"
    next_rook_version_patch="${patch}"

    # rook 1.0 currently running
    if [ "$current_rook_version_major" -eq "1" ] && [ "$current_rook_version_minor" -eq "0" ]; then
           # rook 1.4+ desired
            if [ "$next_rook_version_major" -eq "1" ] && [ "$next_rook_version_minor" -ge "4" ] && [ "$next_rook_version_patch" -ge "9" ]; then
                return 0
            fi
    fi

    return 1
}

# returns zero only when all pods in the rook-ceph namespace share the same rook-version label and that label matches the version provided
function is_rook_rollout_complete() {
    local desired_version=$1

    local current_versions
    current_versions=$(kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{.metadata.labels.rook-version}{"\n"}{end}' | sort | uniq)

    local num_versions
    num_versions=$(echo "$current_versions" | wc -w)

    if [ "$num_versions" -ne "1" ]; then
        # there's more than one version present
        return 1
    fi

    if [ "$current_versions" != "$desired_version" ]; then
        # the current version is not the version we are upgrading to, so the rollout has not yet started
        return 1
    fi
    return 0
}

# returns zero only when all pods in the rook-ceph namespace share the same ceph-version label and that label matches the version provided
function is_ceph_rollout_complete() {
    local desired_version=$1

    local current_versions
    current_versions=$(kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{.metadata.labels.ceph-version}{"\n"}{end}' | sort | uniq)

    local num_versions
    num_versions=$(echo "$current_versions" | wc -w)

    if [ "$num_versions" -ne "1" ]; then
        # there's more than one version present
        return 1
    fi

    if [ "$current_versions" != "$desired_version" ]; then
        # the current version is not the version we are upgrading to, so the rollout has not yet started
        return 1
    fi
    return 0
}

function rook_ceph_tools_exec() {
    local args=$1

    local tools_pod=
    if kubectl -n rook-ceph exec deploy/rook-ceph-tools -- bash -s "$args" ; then
        return 0
    fi
    return 1
}

# upgrades Rook progressively from 1.0.x to 1.4.x
function rook_10_to_14() {
    logStep "Upgrading Rook-Ceph from 1.0.x to 1.4.x"
    echo "This involves upgrading from 1.0.x to 1.1, 1.1 to 1.2, 1.2 to 1.3, and 1.3 to 1.4"
    echo "This may take some time"

    $DIR/bin/kurl rook hostpath-to-block

    logStep "Downloading images required for this upgrade"
    # todo download images and load them so that they aren't being pulled dynamically
    logSuccess "Images loaded for Rook 1.1.9, 1.2.7, 1.3.11 and 1.4.9"

    echo "Rescaling pgs per pool"
    rook_ceph_tools_exec "ceph osd pool ls | grep rook-ceph-store | xargs -I {} ceph osd pool set {} pg_num 16"
    rook_ceph_tools_exec "ceph osd pool ls | grep -v rook-ceph-store | xargs -I {} ceph osd pool set {} pg_num 32"
    $DIR/bin/kurl rook wait-for-health

    logStep "Upgrading to Rook 1.1.9"

    # first update rbac and other resources for 1.1
    # todo store these files ourselves
    curl -sSL https://raw.githubusercontent.com/rook/rook/v1.1.9/cluster/examples/kubernetes/ceph/upgrade-from-v1.0-create.yaml \
      | sed 's/ROOK_SYSTEM_NAMESPACE/rook-ceph/g' | sed 's/ROOK_NAMESPACE/rook-ceph/g' | kubectl create -f -
    curl -sSL https://raw.githubusercontent.com/rook/rook/v1.1.9/cluster/examples/kubernetes/ceph/upgrade-from-v1.0-apply.yaml \
      | sed 's/ROOK_SYSTEM_NAMESPACE/rook-ceph/g' | sed 's/ROOK_NAMESPACE/rook-ceph/g' | kubectl apply -f -

    kubectl delete crd volumesnapshotclasses.snapshot.storage.k8s.io volumesnapshotcontents.snapshot.storage.k8s.io volumesnapshots.snapshot.storage.k8s.io
    kubectl -n rook-ceph set image deploy/rook-ceph-operator rook-ceph-operator=rook/ceph:v1.1.9
    kubectl -n rook-ceph set image deploy/rook-ceph-tools rook-ceph-tools=rook/ceph:v1.1.9
    echo "Waiting for Rook 1.1.9 to rollout throughout the cluster, this may take some time"
    # todo show progress somehow
    spinner_until -1 is_rook_rollout_complete "v1.1.9"
    # todo make sure that the RGW isn't getting stuck
    echo "Rook 1.1.9 has been rolled out throughout the cluster"

    echo "Enabling pg pool autoscaling"
    rook_ceph_tools_exec "ceph osd pool ls | xargs -I {} ceph osd pool set {} pg_autoscale_mode on"

    echo "Upgrading CRDs to Rook 1.1"
    # todo store these files ourselves
    curl -sSL https://raw.githubusercontent.com/rook/rook/v1.1.9/cluster/examples/kubernetes/ceph/upgrade-from-v1.0-crds.yaml | kubectl apply -f -

    # todo upgrade ceph image to 14.2.5 here
    echo "Upgrading ceph to v14.2.5"
    kubectl -n rook-ceph patch CephCluster rook-ceph --type=merge -p '{"spec": {"cephVersion": {"image": "ceph/ceph:v14.2.5-20191210"}}}'
    spinner_until -1 is_ceph_rollout_complete "14.2.5"

    logSuccess "Upgraded to Rook 1.1.9 successfully"
    logStep "Upgrading to Rook 1.2.7"
    $DIR/bin/kurl rook wait-for-health

    echo "Updating resources for Rook 1.2.7"
    # apply RBAC not contained in the git repo for some reason
    kubectl apply -f - << EOM
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: rook-ceph-osd
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: rook-ceph-osd
subjects:
- kind: ServiceAccount
  name: rook-ceph-osd
  namespace: rook-ceph
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: rook-ceph-osd
  namespace: rook-ceph
rules:
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - get
  - list
EOM
    curl -sSL https://raw.githubusercontent.com/rook/rook/v1.2.7/cluster/examples/kubernetes/ceph/upgrade-from-v1.1-apply.yaml | kubectl apply -f -


    kubectl -n rook-ceph set image deploy/rook-ceph-operator rook-ceph-operator=rook/ceph:v1.2.7
    kubectl -n rook-ceph set image deploy/rook-ceph-tools rook-ceph-tools=rook/ceph:v1.2.7
    echo "Waiting for Rook 1.2.7 to rollout throughout the cluster, this may take some time"
    # todo show progress somehow
    spinner_until -1 is_rook_rollout_complete "v1.2.7"
    echo "Rook 1.2.7 has been rolled out throughout the cluster"
    $DIR/bin/kurl rook wait-for-health

    echo "Upgrading CRDs to Rook 1.2"
    curl -sSL https://raw.githubusercontent.com/rook/rook/v1.2.7/cluster/examples/kubernetes/ceph/upgrade-from-v1.1-crds.yaml | kubectl apply -f -

    logSuccess "Upgraded to Rook 1.2.7 successfully"
    logStep "Upgrading to Rook 1.3.11"
    $DIR/bin/kurl rook wait-for-health

    echo "Updating resources for Rook 1.3.11"
    curl -sSL https://raw.githubusercontent.com/rook/rook/v1.3.11/cluster/examples/kubernetes/ceph/upgrade-from-v1.2-apply.yaml | kubectl apply -f -
    curl -sSL https://raw.githubusercontent.com/rook/rook/v1.3.11/cluster/examples/kubernetes/ceph/upgrade-from-v1.2-crds.yaml | kubectl apply -f -
    kubectl -n rook-ceph set image deploy/rook-ceph-operator rook-ceph-operator=rook/ceph:v1.3.11
    kubectl -n rook-ceph set image deploy/rook-ceph-tools rook-ceph-tools=rook/ceph:v1.3.11
    echo "Waiting for Rook 1.3.11 to rollout throughout the cluster, this may take some time"
    # todo show progress somehow
    spinner_until -1 is_rook_rollout_complete "v1.3.11"
    echo "Rook 1.3.11 has been rolled out throughout the cluster"
    $DIR/bin/kurl rook wait-for-health

    logSuccess "Upgraded to Rook 1.3.11 successfully"
    logStep "Upgrading to Rook 1.4.9"

    echo "Updating resources for Rook 1.4.9"
    curl -sSL https://raw.githubusercontent.com/rook/rook/v1.4.9/cluster/examples/kubernetes/ceph/upgrade-from-v1.3-delete.yaml | kubectl delete -f -
    curl -sSL https://raw.githubusercontent.com/rook/rook/v1.4.9/cluster/examples/kubernetes/ceph/upgrade-from-v1.3-apply.yaml | kubectl apply -f -
    curl -sSL https://raw.githubusercontent.com/rook/rook/v1.4.9/cluster/examples/kubernetes/ceph/upgrade-from-v1.3-crds.yaml | kubectl apply -f -
    kubectl -n rook-ceph set image deploy/rook-ceph-operator rook-ceph-operator=rook/ceph:v1.4.9
    kubectl -n rook-ceph set image deploy/rook-ceph-tools rook-ceph-tools=rook/ceph:v1.4.9
    echo "Waiting for Rook 1.4.9 to rollout throughout the cluster, this may take some time"
    # todo show progress somehow
    spinner_until -1 is_rook_rollout_complete "v1.4.9"
    echo "Rook 1.4.9 has been rolled out throughout the cluster"
}
