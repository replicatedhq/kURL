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

    log "Removing rook-ceph Storage Classes"
    if ! kubectl get storageclass | grep rook | awk '{ print $1 }' | xargs -I'{}' kubectl delete storageclass '{}' --timeout=60s; then
        logFail "Unable to delete rook-ceph StorageClasses"
        return 1
    fi

    # More info: https://rook.io/docs/rook/v1.10/Getting-Started/ceph-teardown/#delete-the-cephcluster-crd
    log "Patch Ceph cluster to allow deletion"
    kubectl -n rook-ceph patch cephcluster rook-ceph --type merge -p '{"spec":{"cleanupPolicy":{"confirmation":"yes-really-destroy-data"}}}'

    # remove all rook-ceph CR objects
    log "Removing rook-ceph custom resource objects - this may take some time:\n"
    if ! kubectl delete cephcluster -n rook-ceph rook-ceph --timeout=300s; then
        logFail "Unable to delete the rook-ceph CephCluster resource"
        return 1
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

    log "Removing rook-ceph volumes custom resource"
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
    if kubectl get namespace monitoring &>/dev/null; then
        if kubectl -n monitoring get prometheus k8s &>/dev/null; then
            # before scaling down prometheus, scale down ekco as it will otherwise restore the prometheus scale
            if kubernetes_resource_exists kurl deployment ekc-operator; then
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

        # Just continue if Rook is installed. 
        if ! kubectl get ns | grep -q rook-ceph; then
            return
        fi
        logStep "Removing Rook"

        if [ "$DID_MIGRATE_ROOK_PVCS" == "1" ] && [ "$DID_MIGRATE_ROOK_OBJECT_STORE" == "1" ]; then
            report_addon_start "rook-ceph-removal" "v1"
            if ! remove_rook_ceph; then
                logFail "Unable to remove Rook."
                report_addon_fail "rook-ceph-removal" "v1"
                return
            fi
            report_addon_success "rook-ceph-removal" "v1"
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

function rook_is_healthy_to_upgrade() {
    log "Awaiting Rook Ceph health ..."
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
