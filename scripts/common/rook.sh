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
        # do stuff
        printf "%b" "$RED"
        printf "ERROR: \n"
        printf "There are still PVs using rook-ceph.\n"
        printf "Remove these PVs before continuing.\n"
        printf "%b" "$NC"
        exit 1
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
    kubectl delete --ignore-not-found crd volumes.rook.io

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
    printf "%bRemoved rook-ceph successfully!\n%b" "$GREEN" "$NC"
    printf "Data within /var/lib/rook, /opt/replicated/rook and any bound disks has not been freed.\n"
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
        if [ "$DID_MIGRATE_ROOK_PVCS" == "1" ] && [ "$DID_MIGRATE_ROOK_OBJECT_STORE" == "1" ]; then
            report_addon_start "rook-ceph-removal" "v1"
            remove_rook_ceph
            report_addon_success "rook-ceph-removal" "v1"
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
        logFail "Multiple Ceph versions detected"
        logFail "${ceph_versions_found}"
        return 1
    fi
    return 0
}
