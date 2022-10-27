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
    if kubectl -n rook-ceph get pods -l app=rook-ceph-osd 2>/dev/null | grep 'rook-ceph-osd' &>/dev/null ; then
        return 1
    fi
    return 0
}

function prometheus_pods_gone() {
    if kubectl -n monitoring get pods -l app=prometheus 2>/dev/null | grep 'prometheus' &>/dev/null ; then
        return 1
    fi
    if kubectl -n monitoring get pods -l app.kubernetes.io/name=prometheus 2>/dev/null | grep 'prometheus' &>/dev/null ; then # the labels changed with prometheus 0.53+
        return 1
    fi

    return 0
}

function ekco_pods_gone() {
    if kubectl -n kurl get pods -l app=ekc-operator 2>/dev/null | grep 'ekc' &>/dev/null ; then
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

# scale down prometheus, move all 'rook-ceph' PVCs to provided storage class, scale up prometheus
# Supported storage class migrations from ceph are: 'longhorn' and 'openebs'
function rook_ceph_to_sc_migration() {
    local destStorageClass=$1
    local scProvisioner="$(kubectl get $destStorageClass -ojsonpath='{.provisioner}')"

    # we only support migrating to 'longhorn' and 'openebs' storage classes
    if [ "$scProvisioner" != *"longhorn"* ] && [ "$scProvisioner" != *"openebs"* ]; then
        bail "Ceph to $scProvisioner migration is not supported"
    fi

    report_addon_start "rook-ceph-to-${scProvisioner}-migration" "v2"

    # patch ceph so that it does not consume new devices that longhorn creates
    echo "Patching CephCluster storage.useAllDevices=false"
    kubectl -n rook-ceph patch cephcluster rook-ceph --type json --patch '[{"op": "replace", "path": "/spec/storage/useAllDevices", value: false}]'
    sleep 1
    echo "Waiting for CephCluster to update"
    spinner_until 300 rook_osd_phase_ready || true # don't fail

    # set prometheus scale if it exists
    if kubectl get namespace monitoring &>/dev/null; then
        if kubectl -n monitoring get prometheus k8s &>/dev/null; then
            # before scaling down prometheus, scale down ekco as it will otherwise restore the prometheus scale
            if kubernetes_resource_exists kurl deployment ekc-operator; then
                kubectl -n kurl scale deploy ekc-operator --replicas=0
                echo "Waiting for ekco pods to be removed"
                spinner_until 120 ekco_pods_gone
            fi

            kubectl -n monitoring patch prometheus k8s --type='json' --patch '[{"op": "replace", "path": "/spec/replicas", value: 0}]'
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
        $BIN_PVMIGRATE --source-sc "$rook_sc" --dest-sc "$destStorageClass" --rsync-image "$KURL_UTIL_IMAGE"
    done

    for rook_sc in $rook_default_sc
    do
        # run the migration (setting defaults)
        $BIN_PVMIGRATE --source-sc "$rook_sc" --dest-sc "$destStorageClass" --rsync-image "$KURL_UTIL_IMAGE" --set-defaults
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
    printf "${GREEN}Migration from rook-ceph to %s completed successfully!\n${NC}" "$scProvisioner"
    report_addon_success "rook-ceph-to-$scProvisioner-migration" "v2"
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
    kubectl -n rook-ceph get deploy rook-ceph-operator -oyaml \
        | grep ' image: ' \
        | awk -F':' 'NR==1 { print $3 }' \
        | sed 's/v\([^-]*\).*/\1/'
}

# checks if rook should be upgraded before upgrading k8s. If it should, and the user confirms this, reports that as an addon, and starts the upgrade process.
function maybe_report_upgrade_rook_10_to_14() {
    if should_upgrade_rook_10_to_14; then
        echo "Upgrading Rook will take some time and will place additional load on your server."
        if ! $DIR/bin/kurl rook has-sufficient-blockdevices; then
            echo "In order to complete this migration, you will need to attach a blank disk to each node in the cluster for Rook to use."
        fi
        printf "Would you like to continue? "

        if ! confirmN; then
            echo "Not upgrading Rook"
            return 0
        fi
        report_upgrade_rook_10_to_14
    fi
}

function report_upgrade_rook_10_to_14() {
    ROOK_10_TO_14_VERSION="v1.0.0" # if you change this code, change the version
    report_addon_start "rook_10_to_14" "$ROOK_10_TO_14_VERSION"
    export REPORTING_CONTEXT_INFO="rook_10_to_14 $ROOK_10_TO_14_VERSION"
    rook_10_to_14
    export REPORTING_CONTEXT_INFO=""
    report_addon_success "rook_10_to_14" "$ROOK_10_TO_14_VERSION"
}

# checks the currently installed rook version and the desired rook version
# if the current version is 1.0-3.x and the desired version is 1.4.9+, returns true
function should_upgrade_rook_10_to_14() {
    # rook is not requested to be installed, so no upgrade
    if [ -z "${ROOK_VERSION}" ]; then
        return 1
    fi

    # rook is not currently installed, so no upgrade
    if ! is_rook_1 ; then
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

function rook_10_to_14_images() {
    logStep "Downloading images required for Rook 1.1.9, 1.2.7, 1.3.11 and 1.4.9 that will be used as part of this upgrade"

    if [ "$AIRGAP" = "1" ]; then
        if ! addon_fetch_airgap rookupgrade 10to14; then
            return 1
        fi
    else
        addon_fetch rookupgrade 10to14
    fi

    addon_load rookupgrade 10to14
    logSuccess "Images loaded for Rook 1.1.9, 1.2.7, 1.3.11 and 1.4.9"
}

# upgrades Rook progressively from 1.0.x to 1.4.x
function rook_10_to_14() {
    logStep "Upgrading Rook-Ceph from 1.0.x to 1.4.x"
    echo "This involves upgrading from 1.0.x to 1.1, 1.1 to 1.2, 1.2 to 1.3, and 1.3 to 1.4"
    echo "This may take some time"
    if ! rook_10_to_14_images; then
        logWarn "Cancelling Rook 1.0 to 1.4 upgrade"
        return 0
    fi

    local thisHostname=
    thisHostname=$(hostname)

    local nodesMissingImages=
    nodesMissingImages=$($DIR/bin/kurl cluster nodes-missing-images docker.io/rook/ceph:v1.1.9 docker.io/rook/ceph:v1.2.7 docker.io/rook/ceph:v1.3.11 docker.io/rook/ceph:v1.4.9 --exclude_host $thisHostname)
    if [ -n "$nodesMissingImages" ]; then
        local prefix=
        prefix="$(build_installer_prefix "${INSTALLER_ID}" "${KURL_VERSION}" "${KURL_URL}" "${PROXY_ADDRESS}")"

        echo "The nodes $nodesMissingImages appear to be missing images required for the Rook 1.0 to 1.4 migration."
        echo "Please run the following on each of these nodes before continuing:"
        printf "\n\t${GREEN}${prefix}tasks.sh | sudo bash -s rook_10_to_14_images${NC}\n\n"
        printf "Are you ready to continue? "
        confirmY
    fi

    $DIR/bin/kurl rook hostpath-to-block

    local upgrade_files_path="$DIR/addons/rookupgrade/10to14"

    echo "Rescaling pgs per pool"
    # enabling autoscaling at this point doesn't scale down the number of PGs sufficiently in my testing - it will be enabled after installing 1.4.9
    kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd pool ls | \
      grep rook-ceph-store | \
      xargs -I {} kubectl -n rook-ceph exec deploy/rook-ceph-tools -- \
      ceph osd pool set {} pg_num 16
    kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd pool ls | \
      grep -v rook-ceph-store | \
      xargs -I {} kubectl -n rook-ceph exec deploy/rook-ceph-tools -- \
      ceph osd pool set {} pg_num 32
    $DIR/bin/kurl rook wait-for-health

    logStep "Upgrading to Rook 1.1.9"

    # first update rbac and other resources for 1.1
    kubectl create -f "$upgrade_files_path/upgrade-from-v1.0-create.yaml" || true # resources may already be present
    kubectl apply -f "$upgrade_files_path/upgrade-from-v1.0-apply.yaml"

    # change the default osd pool size from 3 to 1
    kubectl apply -f "$upgrade_files_path/rook-config-override.yaml"

    kubectl delete crd volumesnapshotclasses.snapshot.storage.k8s.io volumesnapshotcontents.snapshot.storage.k8s.io volumesnapshots.snapshot.storage.k8s.io || true # resources may not be present
    kubectl -n rook-ceph set image deploy/rook-ceph-operator rook-ceph-operator=rook/ceph:v1.1.9
    kubectl -n rook-ceph set image deploy/rook-ceph-tools rook-ceph-tools=rook/ceph:v1.1.9
    echo "Waiting for Rook 1.1.9 to rollout throughout the cluster, this may take some time"
    $DIR/bin/kurl rook wait-for-rook-version "v1.1.9"
    # todo make sure that the RGW isn't getting stuck
    echo "Rook 1.1.9 has been rolled out throughout the cluster"

    echo "Upgrading CRDs to Rook 1.1"
    kubectl apply -f "$upgrade_files_path/upgrade-from-v1.0-crds.yaml"

    echo "Upgrading ceph to v14.2.5"
    kubectl -n rook-ceph patch CephCluster rook-ceph --type=merge -p '{"spec": {"cephVersion": {"image": "ceph/ceph:v14.2.5-20191210"}}}'
    kubectl patch deployment -n rook-ceph csi-rbdplugin-provisioner -p '{"spec": {"template": {"spec":{"containers":[{"name":"csi-snapshotter","imagePullPolicy":"IfNotPresent"}]}}}}'
    $DIR/bin/kurl rook wait-for-ceph-version "14.2.5"

    $DIR/bin/kurl rook wait-for-health
    logSuccess "Upgraded to Rook 1.1.9 successfully"
    logStep "Upgrading to Rook 1.2.7"

    echo "Updating resources for Rook 1.2.7"
    # apply RBAC not contained in the git repo for some reason
    kubectl apply -f "$upgrade_files_path/rook-ceph-osd-rbac.yaml"
    kubectl apply -f "$upgrade_files_path/upgrade-from-v1.1-apply.yaml"

    kubectl -n rook-ceph set image deploy/rook-ceph-operator rook-ceph-operator=rook/ceph:v1.2.7
    kubectl -n rook-ceph set image deploy/rook-ceph-tools rook-ceph-tools=rook/ceph:v1.2.7
    echo "Waiting for Rook 1.2.7 to rollout throughout the cluster, this may take some time"
    $DIR/bin/kurl rook wait-for-rook-version "v1.2.7"
    echo "Rook 1.2.7 has been rolled out throughout the cluster"
    $DIR/bin/kurl rook wait-for-health

    echo "Upgrading CRDs to Rook 1.2"
    kubectl apply -f "$upgrade_files_path/upgrade-from-v1.1-crds.yaml"

    $DIR/bin/kurl rook wait-for-health
    logSuccess "Upgraded to Rook 1.2.7 successfully"
    logStep "Upgrading to Rook 1.3.11"

    echo "Updating resources for Rook 1.3.11"
    kubectl apply -f "$upgrade_files_path/upgrade-from-v1.2-apply.yaml"
    kubectl apply -f "$upgrade_files_path/upgrade-from-v1.2-crds.yaml"
    kubectl -n rook-ceph set image deploy/rook-ceph-operator rook-ceph-operator=rook/ceph:v1.3.11
    kubectl -n rook-ceph set image deploy/rook-ceph-tools rook-ceph-tools=rook/ceph:v1.3.11
    echo "Waiting for Rook 1.3.11 to rollout throughout the cluster, this may take some time"
    $DIR/bin/kurl rook wait-for-rook-version "v1.3.11"
    echo "Rook 1.3.11 has been rolled out throughout the cluster"

    $DIR/bin/kurl rook wait-for-health
    logSuccess "Upgraded to Rook 1.3.11 successfully"
    logStep "Upgrading to Rook 1.4.9"

    echo "Updating resources for Rook 1.4.9"
    kubectl delete -f "$upgrade_files_path/upgrade-from-v1.3-delete.yaml"
    kubectl apply -f "$upgrade_files_path/upgrade-from-v1.3-apply.yaml"
    kubectl apply -f "$upgrade_files_path/upgrade-from-v1.3-crds.yaml"
    kubectl -n rook-ceph set image deploy/rook-ceph-operator rook-ceph-operator=rook/ceph:v1.4.9
    kubectl apply -f "$upgrade_files_path/rook-ceph-tools-14.yaml"

    echo "Waiting for Rook 1.4.9 to rollout throughout the cluster, this may take some time"
    $DIR/bin/kurl rook wait-for-rook-version "v1.4.9"

    $DIR/bin/kurl rook wait-for-health

    echo "Rook 1.4.9 has been rolled out throughout the cluster"

    echo "Upgrading ceph to v15.2.8"
    kubectl -n rook-ceph patch CephCluster rook-ceph --type=merge -p '{"spec": {"cephVersion": {"image": "ceph/ceph:v15.2.8-20201217"}}}'
    $DIR/bin/kurl rook wait-for-ceph-version "15.2.8-0"

    echo "Enabling pg pool autoscaling"
    kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd pool ls | \
      xargs -I {} kubectl -n rook-ceph exec deploy/rook-ceph-tools -- \
      ceph osd pool set {} pg_autoscale_mode on
    echo "Current pg pool autoscaling status:"
    kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd pool autoscale-status

    $DIR/bin/kurl rook wait-for-health

    logSuccess "Upgraded to Rook 1.4.9 successfully"
    logSuccess "Successfully upgraded Rook-Ceph from 1.0.x to 1.4.x"
}
