function longhorn_host_init_common() {
    longhorn_install_iscsi_if_missing_common $1
    longhorn_install_nfs_utils_if_missing_common $1
    mkdir -p /var/lib/longhorn
    chmod 700 /var/lib/longhorn
}

function longhorn_install_iscsi_if_missing_common() {
    local src=$1

    if ! systemctl list-units | grep -q iscsid ; then
        case "$LSB_DIST" in
            ubuntu)
                dpkg_install_host_archives "$src" open-iscsi
                ;;

            centos|rhel|ol|rocky|amzn)
                if is_rhel_9_variant ; then
                    yum_ensure_host_package iscsi-initiator-utils
                else
                    yum_install_host_archives "$src" iscsi-initiator-utils
                fi
                ;;
        esac
    fi

    if ! systemctl -q is-active iscsid; then
        systemctl start iscsid
    fi

    if ! systemctl -q is-enabled iscsid; then
        systemctl enable iscsid
    fi
}

function longhorn_install_nfs_utils_if_missing_common() {
    local src=$1

    if ! systemctl list-units | grep -q nfs-utils ; then
        case "$LSB_DIST" in
            ubuntu)
                dpkg_install_host_archives "$src" nfs-common
                ;;

            centos|rhel|ol|rocky|amzn)
                if is_rhel_9_variant ; then
                    yum_ensure_host_package nfs-utils
                else
                    yum_install_host_archives "$src" nfs-utils
                fi
                ;;
        esac
    fi

    if ! systemctl -q is-active nfs-utils; then
        systemctl start nfs-utils
    fi

    if ! systemctl -q is-enabled nfs-utils; then
        systemctl enable nfs-utils
    fi
}

# longhorn_run_pvmigrate calls pvmigrate to migrate longhorn data to a different storage class. if a failure happen
# then rolls back the original number of volumes and replicas.
function longhorn_run_pvmigrate() {
    local longhornStorageClass=$1
    local destStorageClass=$2
    local didRunValidationChecks=$3
    local setDefaults=$4

    local skipFreeSpaceCheckFlag=""
    local skipPreflightValidationFlag=""
    if [ "$didRunValidationChecks" == "1" ]; then
        skipFreeSpaceCheckFlag="--skip-free-space-check"
        skipPreflightValidationFlag="--skip-preflight-validation"
    fi

    local setDefaultsFlag=""
    if [ "$setDefaults" == "1" ]; then
        setDefaultsFlag="--set-defaults"
    fi

    if ! $BIN_PVMIGRATE --source-sc "$longhornStorageClass" --dest-sc "$destStorageClass" --rsync-image "$KURL_UTIL_IMAGE" "$skipFreeSpaceCheckFlag" "$skipPreflightValidationFlag" "$setDefaultsFlag"; then
        longhorn_restore_migration_replicas
        return 1
    fi
    return 0
}

# scale down prometheus, move all 'longhorn' PVCs to provided storage class, scale up prometheus
# Supported storage class migrations from longhorn are: 'rook' and 'openebs'
function longhorn_to_sc_migration() {
    local destStorageClass=$1
    local didRunValidationChecks=$2
    local scProvisioner
    scProvisioner=$(kubectl get sc "$destStorageClass" -ojsonpath='{.provisioner}')

    # we only support migrating to 'rook' and 'openebs' storage classes
    if [[ "$scProvisioner" != *"rook"* ]] && [[ "$scProvisioner" != *"openebs"* ]]; then
        bail "Longhorn to $scProvisioner migration is not supported"
    fi

    report_addon_start "longhorn-to-${scProvisioner}-migration" "v1"

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
            log "Waiting for prometheus pods to be removed"
            spinner_until 300 prometheus_pods_gone
        fi
    fi

    # scale down ekco if kotsadm is using rqlite.
    if kubernetes_resource_exists default statefulset kotsadm-rqlite ; then
        if [ "$ekcoScaledDown" = "0" ]; then
            if kubernetes_resource_exists kurl deployment ekc-operator; then
                kubectl -n kurl scale deploy ekc-operator --replicas=0
                log "Waiting for ekco pods to be removed"
                if ! spinner_until 120 ekco_pods_gone; then
                    logFail "Unable to scale down ekco operator"
                    return 1
                fi
            fi
        fi
    fi

    longhornStorageClasses=$(kubectl get storageclass | grep longhorn | grep -v '(default)' | awk '{ print $1}') # any non-default longhorn StorageClasses
    for longhornStorageClass in $longhornStorageClasses
    do
        if ! longhorn_run_pvmigrate "$longhornStorageClass" "$destStorageClass" "$didRunValidationChecks" "0"; then
            bail "Failed to migrate PVCs from $longhornStorageClass to $destStorageClass"
        fi
    done

    longhornDefaultStorageClass=$(kubectl get storageclass | grep longhorn | grep '(default)' | awk '{ print $1}') # any default longhorn StorageClasses
    for longhornStorageClass in $longhornDefaultStorageClass
    do
        if ! longhorn_run_pvmigrate "$longhornStorageClass" "$destStorageClass" "$didRunValidationChecks" "1"; then
            bail "Failed to migrate PVCs from $longhornStorageClass to $destStorageClass"
        fi
        kubectl annotate storageclass "$longhornStorageClass" storageclass.kubernetes.io/is-default-class-
    done

    longhorn_restore_migration_replicas

    # print success message
    logSuccess "Migration from longhorn to $scProvisioner completed successfully!"
    report_addon_success "longhorn-to-$scProvisioner-migration" "v1"
}

# if PVCs and object store data have both been migrated from longhorn and longhorn is no longer specified in the kURL spec, remove longhorn
function maybe_cleanup_longhorn() {
    if [ -z "$LONGHORN_VERSION" ]; then
        # Just continue if longhorn is installed. 
        if ! kubectl get ns | grep -q longhorn-system; then
            return
        fi 
        logStep "Removing Longhorn"
        if [ "$DID_MIGRATE_LONGHORN_PVCS" == "1" ]; then
            report_addon_start "longhorn-removal" "v1"
            remove_longhorn
            report_addon_success "longhorn-removal" "v1"
            return
        fi

        logFail "Unable to remove Longhorn."
        if [ "$DID_MIGRATE_LONGHORN_PVCS" != "1" ]; then
            logFail "Storage class migration did not succeed"
        fi
    fi
}

# longhorn_pvs_removed returns true when we can't find any pv using the longhorn csi driver.
function longhorn_pvs_removed() {
    local pvs
    pvs=$(kubectl get pv -o=jsonpath='{.items[*].spec.csi.driver}' | grep "longhorn" | wc -l)
    [ "$pvs" = "0" ]
}

# remove_longhorn deletes everything longhorn releated: deployments, CR objects, and CRDs.
function remove_longhorn() {
    # make sure there aren't any PVs using longhorn before deleting it
    log "Waiting for Longhorn PVs to be removed"
    if ! spinner_until 60 longhorn_pvs_removed; then
        # sometimes longhorn hangs and we need to restart kubelet to make it work again, we
        # are going to give this approach a try here before bailing out.
        logWarn "Some Longhorn PVs are still online, trying to restart kubelet."
        systemctl restart kubelet
        log "Waiting for Longhorn PVs to be removed"
        if ! spinner_until 60 longhorn_pvs_removed; then
            logFail "There are still PVs using Longhorn."
            logFail "Remove these PVs before continuing."
            kubectl get pv -o=jsonpath='{.items[*].spec.csi.driver}' | grep "longhorn"
            exit 1
        fi
    fi

    # scale ekco to 0 replicas if it exists
    if kubernetes_resource_exists kurl deployment ekc-operator; then
        kubectl -n kurl scale deploy ekc-operator --replicas=0
        log "Waiting for ekco pods to be removed"
        if ! spinner_until 120 ekco_pods_gone; then
           logWarn "Unable to scale down ekco operator"
        fi
    fi

    # remove longhorn volumes first so the operator can correctly delete them.
    log "Removing Longhorn volumes:"
    kubectl delete volumes.longhorn.io -n longhorn-system --all

    # once volumes have been gone we can remove all other longhorn CR objects.
    log "Removing Longhorn custom resource objects - this may take some time:"
    kubectl get crd | grep 'longhorn' | grep -v 'volumes' | awk '{ print $1 }' | xargs -I'{}' kubectl -n longhorn-system delete '{}' --all

    # delete longhorn CRDs
    log "Removing Longhorn custom resources:"
    kubectl get crd | grep 'longhorn' | awk '{ print $1 }' | xargs -I'{}' kubectl delete crd '{}'

    # delete longhorn ns
    kubectl delete ns longhorn-system

    # delete longhorn storageclass(es)
    log "Removing Longhorn StorageClasses"
    kubectl get storageclass | grep longhorn | awk '{ print $1 }' | xargs -I'{}' kubectl delete storageclass '{}'

    # scale ekco back to 1 replicas if it exists
    if kubernetes_resource_exists kurl deployment ekc-operator; then
        kubectl -n kurl scale deploy ekc-operator --replicas=1
    fi

    logSuccess "Removed Longhorn successfully"
}

# longhorn_prepare_for_migration checks if longhorn is healthy and if it is, it will scale down the all pods mounting
# longhorn volumes. if a failure happen during the preparation fase the migration won't be executed and the user will
# receive a message to restore the cluster to its previous state.
function longhorn_prepare_for_migration() {
    if "$DIR"/bin/kurl longhorn prepare-for-migration; then
        return 0
    fi
    logFail "Preparation for longhorn migration failed. Please review the preceding messages for further details."
    logFail "During the preparation for Longhorn, some replicas may have been scaled down to 0. Would you like to"
    logFail "restore the system to its original state?"
    if confirmY; then
        log "Restoring Longhorn replicas to their original state"
        longhorn_restore_migration_replicas
    fi
    return 1
}

# longhorn_restore_migration_replicas scales up all longhorn volumes, deployment and statefulset replicas to their
# original values.
function longhorn_restore_migration_replicas() {
    "$DIR"/bin/kurl longhorn rollback-migration-replicas
}
