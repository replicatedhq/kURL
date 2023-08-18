# shellcheck disable=SC2148

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
    pods_gone_by_selector kurl app=ekc-operator
}

# rook_disable_ekco_operator disables the ekco operator if it exists.
function rook_disable_ekco_operator() {
    if kubernetes_resource_exists kurl deployment ekc-operator ; then
        log "Scaling down EKCO deployment to 0 replicas"
        kubernetes_scale_down kurl deployment ekc-operator
        log "Waiting for ekco pods to be removed"
        if ! spinner_until 120 ekco_pods_gone; then
             logFail "Unable to scale down ekco operator"
             return 1
        fi
    fi
}

# rook_enable_ekco_operator enables the ekco operator if it exists.
function rook_enable_ekco_operator() {
    if kubernetes_resource_exists kurl deployment ekc-operator ; then
        echo "Scaling up EKCO deployment to 1 replica"
        kubernetes_scale kurl deployment ekc-operator 1
    fi
}

function remove_rook_ceph() {
    # For further information see: https://github.com/rook/rook/blob/v1.11.2/Documentation/Storage-Configuration/ceph-teardown.md
    # make sure there aren't any PVs using rook before deleting it
    all_pv_drivers="$(kubectl get pv -o=jsonpath='{.items[*].spec.csi.driver}')"
    if echo "$all_pv_drivers" | grep "rook" &>/dev/null ; then
        logFail "There are still PVs using rook-ceph."
        logFail "Remove these PV(s) before continuing."
        return 1
    fi

    # scale ekco to 0 replicas if it exists
    if kubernetes_resource_exists kurl deployment ekc-operator; then
        kubectl -n kurl scale deploy ekc-operator --replicas=0
        log "Waiting for ekco pods to be removed"
        if ! spinner_until 120 ekco_pods_gone; then
             logFail "Unable to scale down ekco operator"
             return 1
        fi
    fi

    log "Waiting up to 1 minute to remove rook-ceph pool"
    if ! kubectl delete -n rook-ceph cephblockpool replicapool --timeout=60s; then
        logWarn "Unable to delete rook-ceph pool"
    fi

    log "Waiting up to 1 minute to remove rook-ceph Storage Classes"
    if ! kubectl get storageclass | grep rook | awk '{ print $1 }' | xargs -I'{}' kubectl delete storageclass '{}' --timeout=60s; then
        logFail "Unable to delete rook-ceph StorageClasses"
        return 1
    fi

    # More info: https://github.com/rook/rook/blob/v1.10.12/Documentation/CRDs/Cluster/ceph-cluster-crd.md#cleanup-policy
    log "Patch Ceph cluster to allow deletion"
    kubectl -n rook-ceph patch cephcluster rook-ceph --type merge -p '{"spec":{"cleanupPolicy":{"confirmation":"yes-really-destroy-data"}}}'

    # remove all rook-ceph CR objects
    log "Removing rook-ceph custom resource objects - this may take some time:"
    log "Waiting up to 3 minutes to remove rook-ceph CephCluster resource"
    if ! kubectl delete cephcluster -n rook-ceph rook-ceph --timeout=180s; then
        # More info: https://github.com/rook/rook/blob/v1.10.12/Documentation/Storage-Configuration/ceph-teardown.md#removing-the-cluster-crd-finalizer
        logWarn "Timeout of 3 minutes faced deleting the rook-ceph CephCluster resource"
        logWarn "Removing critical finalizers"
        kubectl -n rook-ceph patch configmap rook-ceph-mon-endpoints --type merge -p '{"metadata":{"finalizers": []}}'
        kubectl -n rook-ceph patch secrets rook-ceph-mon --type merge -p '{"metadata":{"finalizers": []}}'
        log "Waiting up to 2 minutes to remove rook-ceph CephCluster resource after remove critical finalizers"
        if ! kubectl delete cephcluster -n rook-ceph rook-ceph --timeout=120s; then
            logWarn "Timeout of 2 minutes faced deleting the rook-ceph CephCluster resource after finalizers have be removed."
            logWarn "Forcing by removing all finalizers"
            local crd
            for crd in $(kubectl get crd -n rook-ceph | awk '/ceph.rook.io/ {print $1}') ; do
                kubectl get -n rook-ceph "$crd" -o name | \
                xargs -I {} kubectl patch -n rook-ceph {} --type merge -p '{"metadata":{"finalizers": []}}'
            done
            # After remove the finalizers the resources might get deleted without the need to try again
            sleep 20s
            if kubectl get cephcluster -n rook-ceph rook-ceph >/dev/null 2>&1; then
                log "Waiting up to 1 minute to remove rook-ceph CephCluster resource"
                if ! kubectl delete cephcluster -n rook-ceph rook-ceph --timeout=60s; then
                    logFail "Unable to delete the rook-ceph CephCluster resource"
                    return 1
                fi
            else
                log "The rook-ceph CephCluster resource was deleted"
            fi
        fi
    fi

    log "Removing rook-ceph custom resources"
    if ! kubectl get crd | grep 'ceph.rook.io' | awk '{ print $1 }' | xargs -I'{}' kubectl -n rook-ceph delete '{}' --all --timeout=60s; then
        logWarn "Unable to delete the rook-ceph custom resources"
    fi

    log "Removing rook-ceph Volume resources"
    if ! kubectl delete volumes.rook.io --all --timeout=60s; then
        logWarn "Unable to delete rook-ceph Volume resources"
    fi

    log "Waiting for rook-ceph OSD pods to be removed"
    if ! spinner_until 120 rook_ceph_osd_pods_gone; then
        logWarn "rook-ceph OSD pods were not deleted"
    fi

    log "Removing rook-ceph CRDs"
    if ! kubectl get crd | grep 'ceph.rook.io' | awk '{ print $1 }' | xargs -I'{}' kubectl delete crd '{}' --timeout=60s; then
        logWarn "Unable to delete rook-ceph CRDs"
    fi

    log "Removing rook-ceph objectbucket CRDs"
    if ! kubectl get crd | grep 'objectbucket.io' | awk '{ print $1 }' | xargs -I'{}' kubectl delete crd '{}' --timeout=60s; then
        logWarn "Unable to delete rook-ceph CRDs"
    fi

    log "Removing rook-ceph volumes CRD"
    if ! kubectl delete --ignore-not-found crd volumes.rook.io --timeout=60s; then
        logWarn "Unable delete rook-ceph volumes custom resource"
    fi

    log "Removing the rook-ceph Namespace"
    if ! kubectl delete ns rook-ceph --timeout=60s; then
        logFail "Unable to delete the rook-ceph Namespace"
        logFail "These resources are preventing the namespace's deletion:"
        kubectl api-resources --verbs=list --namespaced -o name \
                          | xargs -n 1 kubectl get --show-kind --ignore-not-found -n rook-ceph
        return 1
    fi
    
    # scale ekco back to 1 replicas if it exists
    if kubernetes_resource_exists kurl deployment ekc-operator; then
        kubectl -n kurl get configmap ekco-config -o yaml | \
            sed --expression='s/maintain_rook_storage_nodes:[ ]*true/maintain_rook_storage_nodes: false/g' | \
            kubectl -n kurl apply -f -
        kubectl -n kurl scale deploy ekc-operator --replicas=1
    fi

    rm -rf /var/lib/rook || true
    rm -rf /opt/replicated/rook || true

    if [ -d "/var/lib/rook" ] || [ -d "/opt/replicated/rook" ]; then
        logWarn  "Data within /var/lib/rook, /opt/replicated/rook and any bound disks has not been freed."
    fi

    # print success message
    logSuccess "Removed rook-ceph successfully!"
}

# scale down prometheus, move all 'rook-ceph' PVCs to provided storage class, scale up prometheus
# Supported storage class migrations from ceph are: 'longhorn' and 'openebs'
function rook_ceph_to_sc_migration() {
    local destStorageClass=$1
    local didRunValidationChecks=$2
    local scProvisioner
    scProvisioner=$(kubectl get sc "$destStorageClass" -ojsonpath='{.provisioner}')

    # we only support migrating to 'longhorn' and 'openebs' storage classes
    if [[ "$scProvisioner" != *"longhorn"* ]] && [[ "$scProvisioner" != *"openebs"* ]]; then
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
    local ekcoScaledDown=0
    if kubectl get namespace monitoring &>/dev/null; then
        if kubectl -n monitoring get prometheus k8s &>/dev/null; then
            # before scaling down prometheus, scale down ekco as it will otherwise restore the prometheus scale
            if kubernetes_resource_exists kurl deployment ekc-operator; then
                ekcoScaledDown=1
                kubectl -n kurl scale deploy ekc-operator --replicas=0
                log "Waiting for ekco pods to be removed"
                if ! spinner_until 120 ekco_pods_gone; then
                     logFail "Unable to scale down ekco operator"
                     return 1
                fi
            fi

            kubectl -n monitoring patch prometheus k8s --type='json' --patch '[{"op": "replace", "path": "/spec/replicas", value: 0}]'
            echo "Waiting for prometheus pods to be removed"
            spinner_until 300 prometheus_pods_gone
        fi
    fi

    # scale down ekco if kotsadm is using rqlite.
    if kubernetes_resource_exists default statefulset kotsadm-rqlite ; then
        if [ "$ekcoScaledDown" = "0" ]; then
            if kubernetes_resource_exists kurl deployment ekc-operator; then
                ekcoScaledDown=1
                kubectl -n kurl scale deploy ekc-operator --replicas=0
                log "Waiting for ekco pods to be removed"
                if ! spinner_until 120 ekco_pods_gone; then
                    logFail "Unable to scale down ekco operator"
                    return 1
                fi
            fi
        fi
    fi

    # get the list of StorageClasses that use rook-ceph
    rook_scs=$(kubectl get storageclass | grep rook | grep -v '(default)' | awk '{ print $1}') # any non-default rook StorageClasses
    rook_default_sc=$(kubectl get storageclass | grep rook | grep '(default)' | awk '{ print $1}') # any default rook StorageClasses

    for rook_sc in $rook_scs
    do
        if [ "$didRunValidationChecks" == "1" ]; then
            # run the migration w/o validation checks
            $BIN_PVMIGRATE --source-sc "$rook_sc" --dest-sc "$destStorageClass" --rsync-image "$KURL_UTIL_IMAGE" --skip-free-space-check --skip-preflight-validation
        else
            # run the migration (without setting defaults)
            $BIN_PVMIGRATE --source-sc "$rook_sc" --dest-sc "$destStorageClass" --rsync-image "$KURL_UTIL_IMAGE"
        fi
    done

    for rook_sc in $rook_default_sc
    do
        if [ "$didRunValidationChecks" == "1" ]; then
            # run the migration w/o validation checks
            $BIN_PVMIGRATE --source-sc "$rook_sc" --dest-sc "$destStorageClass" --rsync-image "$KURL_UTIL_IMAGE" --skip-free-space-check --skip-preflight-validation --set-defaults
        else
            # run the migration (setting defaults)
            $BIN_PVMIGRATE --source-sc "$rook_sc" --dest-sc "$destStorageClass" --rsync-image "$KURL_UTIL_IMAGE" --set-defaults
        fi
    done

    # reset ekco scale
    if [ "$ekcoScaledDown" = "1" ] ; then
        kubectl -n kurl scale deploy ekc-operator --replicas=1
    fi

    # reset prometheus scale
    if kubectl get namespace monitoring &>/dev/null; then
        if kubectl get prometheus -n monitoring k8s &>/dev/null; then
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

        # Just continue if Rook is installed. 
        if ! kubectl get ns | grep -q rook-ceph; then
            return
        fi
        logStep "Removing Rook"

        export DID_MIGRATE_ROOK_PVCS=0
        export DID_MIGRATE_ROOK_OBJECT_STORE=0
        DID_MIGRATE_ROOK_PVCS=$(kubectl -n kurl get --ignore-not-found configmap kurl-migration-from-rook -o jsonpath='{ .data.DID_MIGRATE_ROOK_PVCS }')
        DID_MIGRATE_ROOK_OBJECT_STORE=$(kubectl -n kurl get --ignore-not-found configmap kurl-migration-from-rook -o jsonpath='{ .data.DID_MIGRATE_ROOK_OBJECT_STORE }')

        if [ "$DID_MIGRATE_ROOK_PVCS" == "1" ] && [ "$DID_MIGRATE_ROOK_OBJECT_STORE" == "1" ]; then
            report_addon_start "rook-ceph-removal" "v1.1"
            if ! remove_rook_ceph; then
                logFail "Unable to remove Rook."
                report_addon_fail "rook-ceph-removal" "v1.1"
                return
            fi
            kubectl delete configmap kurl-migration-from-rook -n kurl
            report_addon_success "rook-ceph-removal" "v1.1"
            return
        fi

        # If upgrade from Rook to OpenEBS without Minio we cannot remove Rook because
        # we do not know if the solution uses or not ObjectStore and if someone data will not be lost
        if [ "$DID_MIGRATE_ROOK_PVCS" == "1" ] && [ -z "$MINIO_VERSION" ]; then
            if [ -z "$DID_MIGRATE_ROOK_OBJECT_STORE" ] || [ "$DID_MIGRATE_ROOK_OBJECT_STORE" != "1" ]; then
                logWarn "PVC(s) were migrated from Rook but Object Store data was not, as no MinIO version was specified."
                logWarn "Rook will not be automatically removed without migrating Object Store data."
                logWarn ""
                logWarn "If you are sure that Object Store data is not used, you can manually perform this operation"
                logWarn "by running the remove_rook_ceph task:"
                logWarn "$ curl <installer>/task.sh | sudo bash -s remove_rook_ceph, i.e.:"
                logWarn ""
                logWarn "curl https://kurl.sh/latest/tasks.sh | sudo bash -s remove_rook_ceph"
            fi
        fi
        logFail "Unable to remove Rook."
        if [ "$DID_MIGRATE_ROOK_PVCS" != "1" ]; then
           logFail "Storage class migration did not succeed"
        fi

        if [ -n "$MINIO_VERSION" ] && [ "$DID_MIGRATE_ROOK_OBJECT_STORE" != "1" ]; then
           logFail "Object Store migration did not succeed"
        fi
    fi
}

function rook_osd_phase_ready() {
    if [ "$(current_rook_version)" = "1.0.4" ]; then
        [ "$(kubectl -n rook-ceph get cephcluster rook-ceph --template '{{.status.state}}')" = 'Created' ]
    else
        [ "$(kubectl -n rook-ceph get cephcluster rook-ceph --template '{{.status.phase}}')" = 'Ready' ]
    fi
}

function current_rook_version() {
    kubectl -n rook-ceph get deploy rook-ceph-operator -oyaml 2>/dev/null \
        | grep ' image: ' \
        | awk -F':' 'NR==1 { print $3 }' \
        | sed 's/v\([^-]*\).*/\1/'
}

function current_ceph_version() {
    kubectl -n rook-ceph get deployment rook-ceph-mgr-a -o jsonpath='{.metadata.labels.ceph-version}' 2>/dev/null \
        | awk -F'-' '{ print $1 }'
}

function rook_operator_ready() {
    local rook_status_phase=
    local rook_status_msg=
    rook_status_phase=$(kubectl -n rook-ceph get cephcluster rook-ceph --template '{{.status.phase}}')
    rook_status_msg=$(kubectl -n rook-ceph get cephcluster rook-ceph --template '{{.status.message}}')
    if [  "$rook_status_phase" != "Ready"  ]; then
        log "Rook operator is not ready: $rook_status_msg"
        return 1
    fi
    return 0
}

# In certain edge cases, while migrating away from Rook, we may encounter issues.
# Specifically, after we execute a pvmigrate operation to migrate the PVCs and to migrate the Object store, the system
# may transition to an unhealthy state. This problem appears to be connected to specific modules
# [root@rook-ceph-operator-747c86774c-7v95s /]# ceph health detail
# HEALTH_ERR 2 mgr modules have failed
# MGR_MODULE_ERROR 2 mgr modules have failed
#     Module 'dashboard' has failed: error('No socket could be created',)
#     Module 'prometheus' has failed: error('No socket could be created',)
# The proposed workaround ensures a smooth transition during the migration and upgrade processes, ultimately allowing
# for the successful deletion of Rook. To this end, this PR automates the resolution process by rectifying the Rook Ceph
# state and allowing the migration to proceed, given that Rook will be removed in the end. It's important to note that
# this automated fix is only applied during the checks performed when we are in the process of migrating away from Rook
# and when Rook's removal is the intended outcome.
#
# Note this method is a duplication of rook_is_healthy_to_upgrade which now is called in the migration process
# ONLY when we are moving from Rook. We should not try to fix it in other circumstances
function rook_is_healthy_to_migrate_from() {
    log "Awaiting up to 5 minutes to check Rook Ceph Pod(s) are Running"
    if ! spinner_until 300 check_for_running_pods "rook-ceph"; then
        logFail "Rook Ceph has unhealthy Pod(s)"
        return 1
    fi

    log "Awaiting up to 10 minutes to check that Rook Ceph is health"
    if ! $DIR/bin/kurl rook wait-for-health 600 ; then
        logWarn "Rook Ceph is unhealthy"

        output=$(kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status)

        echo ""
        echo output
        echo ""

        if [[ $output == *"Module 'dashboard'"* ]] || [[ $output == *"Module 'prometheus'"* ]]; then
            echo "Disabling Ceph manager modules in order to get Ceph healthy again."
            kubectl -n rook-ceph exec deployment/rook-ceph-tools -- ceph mgr module disable prometheus || true
            kubectl -n rook-ceph exec deployment/rook-ceph-tools -- ceph mgr module disable dashboard || true
        fi

        log "Verify Rook Ceph health after try to fix"
        if ! $DIR/bin/kurl rook wait-for-health 600; then
            kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
            logFail "Rook Ceph is unhealthy"
            return 1
        fi
        return 1
    fi

    log "Checking Rook Ceph versions and replicas"
    kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{.metadata.name}{"  \treq/upd/avl: "}{.spec.replicas}{"/"}{.status.updatedReplicas}{"/"}{.status.readyReplicas}{"  \trook-version="}{.metadata.labels.rook-version}{"\n"}{end}'
    local rook_versions=
    rook_versions="$(kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"rook-version="}{.metadata.labels.rook-version}{"\n"}{end}' | sort | uniq)"
    if [ -n "${rook_versions}" ] && [ "$(echo "${rook_versions}" | wc -l)" -gt "1" ]; then
        logFail "Multiple Rook versions detected"
        logFail "${rook_versions}"
        return 1
    fi

    log "Checking Ceph versions and replicas"
    kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{.metadata.name}{"  \treq/upd/avl: "}{.spec.replicas}{"/"}{.status.updatedReplicas}{"/"}{.status.readyReplicas}{"  \tceph-version="}{.metadata.labels.ceph-version}{"\n"}{end}'
    local ceph_versions_found=
    ceph_versions_found="$(kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"ceph-version="}{.metadata.labels.ceph-version}{"\n"}{end}' | sort | uniq)"
    if [ -n "${ceph_versions_found}" ] && [ "$(echo "${ceph_versions_found}" | wc -l)" -gt "1" ]; then
        # It is required because an Rook Ceph bug which was sorted out with the release 1.4.8
        # More info: https://github.com/rook/rook/pull/6610
        if [ "$(echo "${ceph_versions_found}" | wc -l)" == "2" ] && [ "$(echo "${ceph_versions_found}" | grep "0.0.0-0")" ]; then
            log "Found two ceph versions but one of them is 0.0.0-0 which will be ignored"
            echo "${ceph_versions_found}"
        else
            logFail "Multiple Ceph versions detected"
            logFail "${ceph_versions_found}"
            return 1
        fi
    fi
    return 0
}

function rook_is_healthy_to_upgrade() {
    log "Awaiting up to 5 minutes to check Rook Ceph Pod(s) are Running"
    if ! spinner_until 300 check_for_running_pods "rook-ceph"; then
        logFail "Rook Ceph has unhealthy Pod(s)"
        return 1
    fi

    log "Awaiting up to 10 minutes to check that Rook Ceph is health"
    if ! $DIR/bin/kurl rook wait-for-health 600 ; then
        kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
        logFail "Rook Ceph is unhealthy"
        return 1
    fi

    log "Checking Rook Ceph versions and replicas"
    kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{.metadata.name}{"  \treq/upd/avl: "}{.spec.replicas}{"/"}{.status.updatedReplicas}{"/"}{.status.readyReplicas}{"  \trook-version="}{.metadata.labels.rook-version}{"\n"}{end}'
    local rook_versions=
    rook_versions="$(kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"rook-version="}{.metadata.labels.rook-version}{"\n"}{end}' | sort | uniq)"
    if [ -n "${rook_versions}" ] && [ "$(echo "${rook_versions}" | wc -l)" -gt "1" ]; then
        logFail "Multiple Rook versions detected"
        logFail "${rook_versions}"
        return 1
    fi

    log "Checking Ceph versions and replicas"
    kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{.metadata.name}{"  \treq/upd/avl: "}{.spec.replicas}{"/"}{.status.updatedReplicas}{"/"}{.status.readyReplicas}{"  \tceph-version="}{.metadata.labels.ceph-version}{"\n"}{end}'
    local ceph_versions_found=
    ceph_versions_found="$(kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"ceph-version="}{.metadata.labels.ceph-version}{"\n"}{end}' | sort | uniq)"
    if [ -n "${ceph_versions_found}" ] && [ "$(echo "${ceph_versions_found}" | wc -l)" -gt "1" ]; then
        # It is required because an Rook Ceph bug which was sorted out with the release 1.4.8
        # More info: https://github.com/rook/rook/pull/6610
        if [ "$(echo "${ceph_versions_found}" | wc -l)" == "2" ] && [ "$(echo "${ceph_versions_found}" | grep "0.0.0-0")" ]; then
            log "Found two ceph versions but one of them is 0.0.0-0 which will be ignored"
            echo "${ceph_versions_found}"
        else
            logFail "Multiple Ceph versions detected"
            logFail "${ceph_versions_found}"
            return 1
        fi
    fi
    return 0
}

# Check if the kurl-migration-from-rook exists then, if not creates it
# To add DID_MIGRATE_ROOK_PVCS = "1" in order to track that the PVCs were migrated
function add_rook_pvc_migration_status() {
    if ! kubectl -n kurl get configmap kurl-migration-from-rook 2>/dev/null; then
       log "Creating ConfigMap to track status of migration from Rook"
       kubectl create configmap kurl-migration-from-rook -n kurl
    fi
    kubectl patch configmap kurl-migration-from-rook -n kurl --type merge -p '{"data":{"DID_MIGRATE_ROOK_PVCS":"1"}}'
    export DID_MIGRATE_ROOK_PVCS=1
}

# Check if the kurl-migration-from-rook exists then, if not creates it
# To add DID_MIGRATE_ROOK_OBJECT_STORE = "1" in order to track that the PVCs were migrated
function add_rook_store_object_migration_status() {
    if ! kubectl -n kurl get configmap kurl-migration-from-rook 2>/dev/null; then
       log "Creating ConfigMap to track status of migration from Rook"
       kubectl create configmap kurl-migration-from-rook -n kurl
    fi
    kubectl patch configmap kurl-migration-from-rook -n kurl --type merge -p '{"data":{"DID_MIGRATE_ROOK_OBJECT_STORE":"1"}}'
    export DID_MIGRATE_ROOK_OBJECT_STORE=1
}

# rook_maybe_migrate_from_openebs may migrate data from OpenEBS to Rook when all the following
# conditions are met:
# - Ekco version is >= 0.27.1.
# - OpenEBS and Rook are selected on the Installer.
# - Rook's minimum node count is set to a value > 1.
# - The number of nodes on the cluster is >= than the Rook minimum node count.
# - The 'scaling' storage class exists.
function rook_maybe_migrate_from_openebs() {
    semverCompare "$EKCO_VERSION" "0.27.1"
    if [ "$SEMVER_COMPARE_RESULT" -lt "0" ]; then
        return 0
    fi
    if [ -z "$ROOK_VERSION" ] || [ -z "$OPENEBS_VERSION" ]; then
        return 0
    fi
    if [ -z "$ROOK_MINIMUM_NODE_COUNT" ] || [ "$ROOK_MINIMUM_NODE_COUNT" -lt "3" ]; then
        return 0
    fi
    rook_maybe_migrate_from_openebs_internal
}

# rook_maybe_migrate_from_openebs_internal SHOULD NOT BE CALLED DIRECTLY.
# it is called by rook_maybe_migrate_from_openebs and rook_maybe_migrate_from_openebs_tasks when all the conditions are met.
# it will check that the required environment variables (EKCO_AUTH_TOKEN and EKCO_ADDRESS) are set and then
# check EKCO to see if the migration is available. If it is, it will prompt the user to start it.
function rook_maybe_migrate_from_openebs_internal() {
    if [ -z "$EKCO_AUTH_TOKEN" ]; then
        logFail "Internal Error: an authentication token is required to start the OpenEBS to Rook multi-node migration."
        return 0
    fi

    if [ -z "$EKCO_ADDRESS" ]; then
        logFail "Internal Error: unable to determine network address of the kURL operator."
        return 0
    fi

    # check if OpenEBS to Rook multi-node migration is available - if it is, prompt the user to start it
    if cluster_status_msg=$("${DIR}"/bin/kurl cluster migrate-multinode-storage --ekco-address "$EKCO_ADDRESS" --ekco-auth-token "$EKCO_AUTH_TOKEN" --check-status 2>&1); then
        printf "    The installer detected both OpenEBS and Rook installations in your cluster. Migration from OpenEBS to Rook\n"
        printf "    is possible now, but it requires scaling down applications using OpenEBS volumes, causing downtime. You can\n"
        printf "    choose to run the migration later if preferred.\n"
        printf "Would you like to continue with the migration now? \n"
        if ! confirmN ; then
            printf "Not migrating from OpenEBS to Rook\n"
            return 0
        fi
    else
        # migration is not available, so exit
        printf "Migration from OpenEBS to Rook is not available: %s\n" "$(echo $cluster_status_msg | sed s/'Error: '//)"
        return 0
    fi

    # Initiate OpenEBS to Rook multi-node migration
    if ! "${DIR}"/bin/kurl cluster migrate-multinode-storage --ekco-address "$EKCO_ADDRESS" --ekco-auth-token "$EKCO_AUTH_TOKEN" --ready-timeout "$(storage_migration_ready_timeout)" --assume-yes; then
        logFail "Failed to migrate from OpenEBS to Rook. The installation will move on."
        logFail "If you would like to run the migration later, run the following command:"
        logFail "    $DIR/bin/kurl cluster migrate-multinode-storage --ekco-address $EKCO_ADDRESS --ekco-auth-token $EKCO_AUTH_TOKEN"
        return 0
    fi
}

# rook_maybe_migrate_from_openebs_tasks will call rook_maybe_migrate_from_openebs_internal
# after determining values for EKCO_AUTH_TOKEN and EKCO_ADDRESS from the cluster.
function rook_maybe_migrate_from_openebs_tasks() {
    local ekcoAddress=
    local ekcoAuthToken=
    ekcoAddress=$(get_ekco_addr)
    ekcoAuthToken=$(get_ekco_storage_migration_auth_token)
    if [ -z "$ekcoAddress" ] || [ -z "$ekcoAuthToken" ]; then
        return 0
    fi

    export EKCO_ADDRESS="$ekcoAddress"
    export EKCO_AUTH_TOKEN="$ekcoAuthToken"

    # are both rook and openebs installed, not just specified?
    if ! kubectl get ns | grep -q rook-ceph && ! kubectl get ns | grep -q openebs; then
        bail "Rook and OpenEBS must be installed in order to migrate to multi-node storage"
    fi

    rook_maybe_migrate_from_openebs_internal
}
