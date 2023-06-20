# shellcheck disable=SC2148

function openebs_pre_init() {
    if [ -z "$OPENEBS_NAMESPACE" ]; then
        OPENEBS_NAMESPACE=openebs
    fi
    if [ -z "$OPENEBS_LOCALPV_STORAGE_CLASS" ]; then
        OPENEBS_LOCALPV_STORAGE_CLASS=openebs-localpv
    fi
    if [ "$OPENEBS_CSTOR" = "1" ]; then
        bail "cstor is not supported on OpenEBS $OPENEBS_APP_VERSION."
    fi

    export OPENEBS_APP_VERSION="__OPENEBS_APP_VERSION__"
    export PREVIOUS_OPENEBS_VERSION="$(openebs_get_running_version)"

    openebs_bail_unsupported_upgrade
    openebs_prompt_migrate_from_rook
    openebs_prompt_migrate_from_longhorn
}

function openebs() {
    local src="$DIR/addons/openebs/$OPENEBS_VERSION"
    local dst="$DIR/kustomize/openebs"

    secure_openebs

    openebs_apply_crds

    # migrate resources that are changing names
    openebs_migrate_pre_helm_resources

    openebs_apply_operator

    # migrate resources that are changing names
    openebs_migrate_post_helm_resources

    openebs_apply_storageclasses

    # if there is a validatingWebhookConfiguration, wait for the service to be ready
    openebs_await_admissionserver

    # migrate from Rook/Ceph storage if applicable
    openebs_maybe_migrate_from_rook

    # migrate from Longhorn storage if applicable
    openebs_maybe_migrate_from_longhorn

    # remove NDM pods if applicable
    openebs_cleanup_ndm
}

# if rook-ceph is installed but is not specified in the kURL spec, migrate data from 
# rook-ceph to OpenEBS local pv hostpath
function openebs_maybe_migrate_from_rook() {
    if [ -z "$ROOK_VERSION" ]; then
        if kubectl get ns | grep -q rook-ceph; then
            # show validation errors from pvmigrate
            # if there are errors, openebs_maybe_rook_migration_checks() will bail
            openebs_maybe_rook_migration_checks
            rook_ceph_to_sc_migration "$OPENEBS_LOCALPV_STORAGE_CLASS" "1"
            # used to automatically delete rook-ceph if object store data was also migrated
            add_rook_pvc_migration_status # used to automatically delete rook-ceph if object store data was also migrated
        fi
    fi
}

function openebs_maybe_rook_migration_checks() {
    logStep "Running Rook to OpenEBS migration checks ..."

    if ! rook_is_healthy_to_migrate_from; then
        bail "Cannot upgrade from Rook to OpenEBS. Rook Ceph is unhealthy."
    fi

    log "Awaiting 2 minutes to check OpenEBS Pod(s) are Running"
    if ! spinner_until 120 check_for_running_pods "$OPENEBS_NAMESPACE"; then
        logFail "OpenEBS has unhealthy Pod(s). Check the namespace $OPENEBS_NAMESPACE "
        bail "Cannot upgrade from Rook to OpenEBS. OpenEBS is unhealthy."
    fi

    # get the list of StorageClasses that use rook-ceph
    local rook_scs
    local rook_default_sc
    rook_scs=$(kubectl get storageclass | grep rook | grep -v '(default)' | awk '{ print $1}') # any non-default rook StorageClasses
    rook_default_sc=$(kubectl get storageclass | grep rook | grep '(default)' | awk '{ print $1}') # any default rook StorageClasses

    # Ensure openebs-localpv-provisioner deployment is ready
    log "awaiting openebs-localpv-provisioner deployment"
    spinner_until 120 deployment_fully_updated openebs openebs-localpv-provisioner

    local rook_scs_pvmigrate_dryrun_output
    local rook_default_sc_pvmigrate_dryrun_output
    for rook_sc in $rook_scs
    do
        # run validation checks for non default Rook storage classes
        if ! rook_scs_pvmigrate_dryrun_output=$($BIN_PVMIGRATE --source-sc "$rook_sc" --dest-sc "$OPENEBS_LOCALPV_STORAGE_CLASS" --rsync-image "$KURL_UTIL_IMAGE" --preflight-validation-only) ; then
            break
        fi
    done

    if [ -n "$rook_default_sc" ] ; then
        # run validation checks for Rook default storage class
        rook_default_sc_pvmigrate_dryrun_output=$($BIN_PVMIGRATE --source-sc "$rook_default_sc" --dest-sc "$OPENEBS_LOCALPV_STORAGE_CLASS" --rsync-image "$KURL_UTIL_IMAGE" --preflight-validation-only || true)
    fi

    if [ -n "$rook_scs_pvmigrate_dryrun_output" ] || [ -n "$rook_default_sc_pvmigrate_dryrun_output" ] ; then
        log "$rook_scs_pvmigrate_dryrun_output"
        log "$rook_default_sc_pvmigrate_dryrun_output"
        bail "Cannot upgrade from Rook to OpenEBS due to previous error."
    fi

    logSuccess "Rook to OpenEBS migration checks completed successfully."
}

function openebs_prompt_migrate_from_rook() {
    local ceph_disk_usage_total
    local rook_ceph_exec_deploy=rook-ceph-operator

    # skip on new install or when Rook is specified in the kURL spec
    if [ -z "$CURRENT_KUBERNETES_VERSION" ] || [ -n "$ROOK_VERSION" ]; then
        return 0
    fi

    # do not proceed if Rook is not installed
    if ! kubectl get ns | grep -q rook-ceph; then
        return 0
    fi

    if kubectl get deployment -n rook-ceph rook-ceph-tools &>/dev/null; then
        rook_ceph_exec_deploy=rook-ceph-tools
    fi
    ceph_disk_usage_total=$(kubectl exec -n rook-ceph deployment/$rook_ceph_exec_deploy -- ceph df | grep TOTAL | awk '{ print $8$9 }')

    printf "${YELLOW}"
    printf "\n"
    printf "    Detected Rook is running in the cluster. Data migration will be initiated to move data from rook-ceph to storage class %s.\n" "$OPENEBS_LOCALPV_STORAGE_CLASS"
    printf "\n"
    printf "    As part of this, all pods mounting PVCs will be stopped, taking down the application.\n"
    printf "\n"
    printf "    Copying the data currently stored within rook-ceph will require at least %s of free space across the cluster.\n" "$ceph_disk_usage_total"
    printf "    It is recommended to take a snapshot or otherwise back up your data before proceeding.\n${NC}"
    printf "\n"
    printf "Would you like to continue? "

    if ! confirmN; then
        bail "Not migrating"
    fi

}

function openebs_apply_crds() {
    local src="$DIR/addons/openebs/$OPENEBS_VERSION/spec/crds"
    local dst="$DIR/kustomize/openebs/spec/crds"

    mkdir -p "$dst"

    cp "$src/kustomization.yaml" "$dst/"
    cp "$src/crds.yaml" "$dst/"

    kubectl apply -k "$dst/"
}

function openebs_apply_operator() {
    local src="$DIR/addons/openebs/$OPENEBS_VERSION/spec"
    local dst="$DIR/kustomize/openebs/spec"

    mkdir -p "$dst"

    render_yaml_file_2 "$src/tmpl-kustomization.yaml" > "$dst/kustomization.yaml"
    render_yaml_file_2 "$src/tmpl-namespace.yaml" > "$dst/namespace.yaml"
    cat "$src/openebs.tmpl.yaml" | sed "s/__OPENEBS_NAMESPACE__/$OPENEBS_NAMESPACE/" > "$dst/openebs.yaml"

    kubectl apply -k "$dst/"

    logStep "Waiting for OpenEBS CustomResourceDefinitions to be ready"
    spinner_until 120 kubernetes_resource_exists default crd blockdevices.openebs.io

    openebs_cleanup_kubesystem
    logSuccess "OpenEBS CustomResourceDefinitions are ready"
}

function openebs_apply_storageclasses() {
    # allow vendor to add custom storageclasses rather than the ones built into add-on
    if [ "$OPENEBS_LOCALPV" != "1" ]; then
        return
    fi

    local src="$DIR/addons/openebs/$OPENEBS_VERSION/spec/storage"
    local dst="$DIR/kustomize/openebs/spec/storage"

    mkdir -p "$dst"

    cp "$src/kustomization.yaml" "$dst/"

    if [ "$OPENEBS_LOCALPV" = "1" ]; then
        report_addon_start "openebs-localpv" "$OPENEBS_APP_VERSION"

        render_yaml_file_2 "$src/tmpl-localpv-storage-class.yaml" > "$dst/localpv-storage-class.yaml"
        insert_resources "$dst/kustomization.yaml" localpv-storage-class.yaml

        if openebs_should_be_default_storageclass "$OPENEBS_LOCALPV_STORAGE_CLASS" ; then
            echo "OpenEBS LocalPV will be installed as the default storage class."
            render_yaml_file_2 "$src/tmpl-patch-localpv-default.yaml" > "$dst/patch-localpv-default.yaml"
            insert_patches_strategic_merge "$dst/kustomization.yaml" patch-localpv-default.yaml
        else
            logWarn "Existing default storage class that is not OpenEBS LocalPV detected."
            logWarn "OpenEBS LocalPV will be installed as the non-default storage class."
        fi

        report_addon_success "openebs-localpv" "$OPENEBS_APP_VERSION"
    fi

    kubectl apply -k "$dst/"
}

function openebs_await_admissionserver() {
    sleep 1
    if kubectl get validatingWebhookConfiguration openebs-validation-webhook-cfg &>/dev/null ; then
        logStep "Waiting for OpenEBS admission controller service to be ready"
        spinner_until 120 kubernetes_service_healthy "$OPENEBS_NAMESPACE" admission-server-svc
        logSuccess "OpenEBS admission controller service is ready"
    fi
}

function openebs_join() {
    secure_openebs
}

function openebs_get_running_version() {
    if kubectl get ns "$OPENEBS_NAMESPACE" >/dev/null 2>&1 ; then
        kubectl -n "$OPENEBS_NAMESPACE" get deploy openebs-provisioner -o jsonpath='{.metadata.labels.openebs\.io/version}' 2>/dev/null
    fi
}

# upgrading non-cstor openebs works from 1.x
function openebs_bail_unsupported_upgrade() {
    if [ -z "$PREVIOUS_OPENEBS_VERSION" ]; then
        return 0
    fi
}

function secure_openebs() {
    mkdir -p /var/openebs
    chmod 700 /var/openebs
}

function openebs_cleanup_kubesystem() {
    # cleanup old kube-system statefulsets
    # https://github.com/openebs/upgrade/blob/v2.12.2/docs/upgrade.md#prerequisites-1
    kubectl -n kube-system delete sts openebs-cstor-csi-controller 2>/dev/null || true
    kubectl -n kube-system delete ds openebs-cstor-csi-node 2>/dev/null || true
    kubectl -n kube-system delete sa openebs-cstor-csi-controller-sa,openebs-cstor-csi-node-sa 2>/dev/null || true
}

function openebs_migrate_pre_helm_resources() {
    # name changed from maya-apiserver-service > openebs-apiservice
    kubectl -n "$OPENEBS_NAMESPACE" delete service maya-apiserver-service 2>/dev/null || true
    # name changed from cvc-operator-service > openebs-cstor-cvc-operator-svc
    kubectl -n "$OPENEBS_NAMESPACE" delete service cvc-operator-service 2>/dev/null || true
    # name changed from maya-apiserver >openebs-apiserver
    kubectl -n "$OPENEBS_NAMESPACE" delete deployment maya-apiserver 2>/dev/null || true
    # name changed from cspc-operator > openebs-cstor-cspc-operator
    kubectl -n "$OPENEBS_NAMESPACE" delete deployment cspc-operator 2>/dev/null || true
    # name changed from cvc-operator > openebs-cstor-cvc-operator
    kubectl -n "$OPENEBS_NAMESPACE" delete deployment cvc-operator 2>/dev/null || true

    # the selectors for these resources changed
    kubectl -n "$OPENEBS_NAMESPACE" delete deployment openebs-localpv-provisioner 2>/dev/null || true
    kubectl -n "$OPENEBS_NAMESPACE" delete deployment openebs-ndm-operator 2>/dev/null || true
    kubectl -n "$OPENEBS_NAMESPACE" delete daemonset openebs-ndm 2>/dev/null || true
    kubectl -n "$OPENEBS_NAMESPACE" delete deployment openebs-provisioner 2>/dev/null || true
    kubectl -n "$OPENEBS_NAMESPACE" delete deployment openebs-snapshot-operator 2>/dev/null || true

    # cleanup admission webhook
    kubectl delete validatingWebhookConfiguration openebs-validation-webhook-cfg 2>/dev/null || true
    kubectl -n "$OPENEBS_NAMESPACE" delete deployment openebs-admission-server 2>/dev/null || true
    kubectl -n "$OPENEBS_NAMESPACE" delete service admission-server-svc 2>/dev/null || true
}

function openebs_migrate_post_helm_resources() {
    # name changed from openebs-maya-operator > openebs
    kubectl delete serviceaccount openebs-maya-operator 2>/dev/null || true
    # name changed from openebs-maya-operator > openebs
    kubectl delete clusterrole openebs-maya-operator 2>/dev/null || true
    # name changed from openebs-maya-operator > openebs
    kubectl delete clusterrolebinding openebs-maya-operator 2>/dev/null || true
}

function openebs_should_be_default_storageclass() {
    local storage_class_name="$1"
    if openebs_is_default_storageclass "$storage_class_name" ; then
        # if "$storage_class_name" is already the default
        return 0
    elif openebs_has_default_storageclass ; then
        # if there is already a default storage class that is not "$storage_class_name"
        return 1
    elif [ -n "$ROOK_MINIMUM_NODE_COUNT" ] && [ "$ROOK_MINIMUM_NODE_COUNT" -gt "1" ]; then
        # if dynamic storage is enabled, the default storageclass will be managed by ekco
        return 1
    elif [ "$storage_class_name" = "default" ]; then
        # if "$storage_class_name" named "default", it should be the default
        return 0
    elif [ -n "$LONGHORN_VERSION" ]; then
        # To maintain backwards compatibility with previous versions of kURL, only make OpenEBS the default
        # if Longhorn is not installed or the storageclass is explicitly named "default"
        return 1
    else
        # if there is no other storageclass, make "$storage_class_name" the default
        return 0
    fi
}

function openebs_is_default_storageclass() {
    local storage_class_name="$1"
    if [ "$(kubectl get sc "$storage_class_name" -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null)" = "true" ]; then
        return 0
    fi
    return 1
}

function openebs_has_default_storageclass() {
    if kubectl get sc -o jsonpath='{.items[*].metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' | grep -q "true" ; then
        return 0
    fi
    return 1
}

# if longhorn is installed but is not specified in the kURL spec, migrate data to OpenEBS local pv hostpath.
function openebs_maybe_migrate_from_longhorn() {
    if [ -z "$LONGHORN_VERSION" ]; then
        if kubectl get ns | grep -q longhorn-system; then
            # show validation errors from pvmigrate if there are errors, openebs_maybe_longhorn_migration_checks() will bail
            openebs_maybe_longhorn_migration_checks

            longhorn_to_sc_migration "$OPENEBS_LOCALPV_STORAGE_CLASS" "1"
            DID_MIGRATE_LONGHORN_PVCS=1 # used to automatically delete longhorn if object store data was also migrated
        fi
    fi
}

function openebs_maybe_longhorn_migration_checks() {
    logStep "Running Longhorn to OpenEBS migration checks"

    log "Awaiting 2 minutes to check OpenEBS Pod(s) are Running"
    if ! spinner_until 120 check_for_running_pods "$OPENEBS_NAMESPACE"; then
        logFail "OpenEBS has unhealthy Pod(s). Check the namespace $OPENEBS_NAMESPACE "
        bail "Cannot upgrade from Rook to OpenEBS. OpenEBS is unhealthy."
    fi

    log "Awaiting 2 minutes to check Longhorn Pod(s) are Running"
    if ! spinner_until 120 check_for_running_pods longhorn-system; then
        logFail "Longhorn has unhealthy Pod(s). Check the namespace longhorn-system"
        bail "Cannot upgrade from Longhorn to OpenEBS. Longhorn is unhealthy."
    fi

    # get the list of StorageClasses that use longhorn
    local longhorn_scs
    local longhorn_default_sc
    longhorn_scs=$(kubectl get storageclass | grep longhorn | grep -v '(default)' | awk '{ print $1}') # any non-default longhorn StorageClasses
    longhorn_default_sc=$(kubectl get storageclass | grep longhorn | grep '(default)' | awk '{ print $1}') # any default longhorn StorageClasses

    # Ensure openebs-localpv-provisioner deployment is ready
    log "Awaiting openebs-localpv-provisioner deployment"
    spinner_until 120 deployment_fully_updated openebs openebs-localpv-provisioner

    local longhorn_scs_pvmigrate_dryrun_output
    local longhorn_default_sc_pvmigrate_dryrun_output
    for longhorn_sc in $longhorn_scs
    do
        # run validation checks for non default Longhorn storage classes
        if longhorn_scs_pvmigrate_dryrun_output=$($BIN_PVMIGRATE --source-sc "$longhorn_sc" --dest-sc "$OPENEBS_LOCALPV_STORAGE_CLASS" --rsync-image "$KURL_UTIL_IMAGE" --preflight-validation-only 2>&1) ; then
            longhorn_scs_pvmigrate_dryrun_output=""
        else
            break
        fi
    done

    if [ -n "$longhorn_default_sc" ] ; then
        # run validation checks for Longhorn default storage class
        if longhorn_default_sc_pvmigrate_dryrun_output=$($BIN_PVMIGRATE --source-sc "$longhorn_default_sc" --dest-sc "$OPENEBS_LOCALPV_STORAGE_CLASS" --rsync-image "$KURL_UTIL_IMAGE" --preflight-validation-only 2>&1) ; then
            longhorn_default_sc_pvmigrate_dryrun_output=""
        fi
    fi

    if [ -n "$longhorn_scs_pvmigrate_dryrun_output" ] || [ -n "$longhorn_default_sc_pvmigrate_dryrun_output" ] ; then
        log "$longhorn_scs_pvmigrate_dryrun_output"
        log "$longhorn_default_sc_pvmigrate_dryrun_output"
        longhorn_restore_migration_replicas
        bail "Cannot upgrade from Longhorn to OpenEBS due to previous error."
    fi

    logSuccess "Longhorn to OpenEBS migration checks completed."
}

# shows a prompt asking users for confirmation before starting to migrate data from Longhorn.
function openebs_prompt_migrate_from_longhorn() {
    # skip on new install or when Longhorn is specified in the kURL spec
    if [ -z "$CURRENT_KUBERNETES_VERSION" ] || [ -n "$LONGHORN_VERSION" ]; then
        return 0
    fi

    # do not proceed if Longhorn is not installed
    if ! kubectl get ns | grep -q longhorn-system; then
        return 0
    fi

    logWarn "    Detected Longhorn is running in the cluster. Data migration will be initiated to move data from Longhorn to storage class $OPENEBS_LOCALPV_STORAGE_CLASS."
    logWarn "    As part of this, all pods mounting PVCs will be stopped, taking down the application."
    logWarn "    It is recommended to take a snapshot or otherwise back up your data before proceeding."

    semverParse "$KUBERNETES_VERSION"
    if [ "$minor" -gt 24 ] ; then
        logFail "    It appears that the Kubernetes version you are attempting to install ($KUBERNETES_VERSION) is incompatible with the version of Longhorn currently installed"
        logFail "    on your cluster. As a result, it is not possible to migrate data from Longhorn to OpenEBS. To successfully migrate data, please choose a Kubernetes"
        logFail "    version that is compatible with the version of Longhorn running on your cluster (note: Longhorn is compatible with Kubernetes versions up to and"
        logFail "    including 1.24)."
        bail "Not migrating"
    fi

    log "Would you like to continue? "
    if ! confirmN; then
        bail "Not migrating"
    fi

    if ! longhorn_prepare_for_migration; then
        bail "Not migrating"
    fi
}

function openebs_cleanup_ndm() {
    kubectl delete --ignore-not-found configmap -n "$OPENEBS_NAMESPACE" openebs-ndm-config
    kubectl delete --ignore-not-found daemonset -n "$OPENEBS_NAMESPACE" openebs-ndm
    kubectl delete --ignore-not-found deployment -n "$OPENEBS_NAMESPACE" openebs-ndm-operator
}
