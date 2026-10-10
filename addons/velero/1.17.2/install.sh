# shellcheck disable=SC2148
# kotsadm versions earlier than this re-configure Velero onto the Local Volume Provider
# even when an object store is present, so they must be upgraded before the
# Local Volume Provider -> object store migration can run.
VELERO_MIN_KOTSADM_VERSION="1.131.6"

function velero_pre_init() {
    if [ -z "$VELERO_NAMESPACE" ]; then
        VELERO_NAMESPACE=velero
    fi
    if [ -z "$VELERO_LOCAL_BUCKET" ]; then
        VELERO_LOCAL_BUCKET=velero
    fi
    # TODO (dans): make this configurable from the installer spec
    # if [ -z "$VELERO_REQUESTED_CLAIM_SIZE" ]; then
    #     VELERO_REQUESTED_CLAIM_SIZE="50Gi"
    # fi

    # If someone is trying to use only Rook 1.0.4, RWX volumes are not supported
    if [ "$ROOK_VERSION" = "1.0.4" ] && [ -z "$LONGHORN_VERSION" ] && [ "$KOTSADM_DISABLE_S3" == 1 ]; then
        bail "Rook 1.0.4 does not support RWX volumes used for Internal snapshot storage. Please upgrade to Rook 1.4.3 or higher."
    fi

    # The PVC-based Internal Storage destination requires an RWX storage class, but the
    # Local Volume Provider also supports Host Path and NFS destinations which are
    # configured by KOTS after the installer completes, so a missing Rook/Longhorn is not
    # an error. When no RWX storage class is available the install falls back to
    # --no-default-backup-location (see velero_install).

    if [ "$KUBERNETES_TARGET_VERSION_MINOR" -lt 25 ]; then
        semverCompare "${VELERO_VERSION//v/}" "1.16.2"
        if [ "$SEMVER_COMPARE_RESULT" != "-1" ]; then # greater than or equal to 1.16.2
            bail "Velero $VELERO_VERSION is not supported on Kubernetes versions less than 1.25"
        fi
    fi

    if velero_version_ge "1.17.0"; then
        velero_pre_init_117_gate
    fi

    velero_host_init
}

# Velero 1.17+ uses Kopia and no longer supports the Local Volume Provider snapshot
# destinations offered in the Admin Console (Network File System (NFS), Host Path and
# Internal Storage). If the cluster is using one, either migrate it to the in-cluster
# object store during this upgrade (when possible) or block with an actionable message.
function velero_pre_init_117_gate() {
    if [ "$KOTSADM_DISABLE_S3" == 1 ]; then
        bail "Velero $VELERO_VERSION does not support the NFS, Host Path or Internal Storage snapshot destinations selected with kotsadm.disableS3. Velero 1.17+ uses Kopia, which requires an S3-compatible object store. Add Minio or Rook to the installer, configure an external S3-compatible object store, or pin Velero to a version earlier than 1.17. See https://community.replicated.com/t/upgrade-guide-velero-1-16-to-1-17-on-kurl-kots-with-lvp-snapshots/1647 for more information."
    fi

    if ! velero_using_local_volume_provider; then
        return 0
    fi

    local lvp_destination
    lvp_destination=$(velero_lvp_destination_name)

    if velero_should_migrate_lvp_to_object_store; then
        log "Velero is using the $lvp_destination snapshot destination, which is not supported by Velero 1.17+. It will be migrated to the in-cluster object store during this upgrade."
        return 0
    fi

    if ! velero_object_store_available_for_migration; then
        bail "Velero $VELERO_VERSION cannot be used with the $lvp_destination snapshot destination because Velero 1.17+ uses Kopia, which does not support it. Snapshots taken with the $lvp_destination destination will not be restorable after the upgrade. To upgrade, add Minio or Rook to the installer, configure an external S3-compatible object store, or pin Velero to a version earlier than 1.17. Manual migration steps: https://community.replicated.com/t/upgrade-guide-velero-1-16-to-1-17-on-kurl-kots-with-lvp-snapshots/1647"
    fi

    bail "Velero $VELERO_VERSION cannot be upgraded from the $lvp_destination snapshot destination until kotsadm is upgraded to $VELERO_MIN_KOTSADM_VERSION or later, because older versions of kotsadm re-configure Velero back onto the $lvp_destination destination even when an object store is present. Re-run the installer with kotsadm $VELERO_MIN_KOTSADM_VERSION or later, or pin Velero to a version earlier than 1.17."
}

# runs on first install, and on version upgrades only
function velero() {
    local src="$DIR/addons/velero/$VELERO_VERSION"
    local dst="$DIR/kustomize/velero"

    render_yaml_file "$src/tmpl-troubleshoot.yaml" > "$dst/troubleshoot.yaml"
    render_yaml_file "$src/tmpl-kustomization.yaml" > "$dst/kustomization.yaml"

    velero_binary

    # If the cluster is on the Local Volume Provider and an object store is available,
    # migrate before the install so that a new object store BackupStorageLocation is
    # created (gated in velero_pre_init)
    if velero_should_migrate_lvp_to_object_store; then
        velero_migrate_lvp_to_object_store
    fi

    determine_velero_pvc_size

    velero_install "$src" "$dst"

    velero_patch_node_agent_privilege "$src" "$dst"

    velero_patch_args "$src" "$dst"

    velero_kotsadm_restore_config "$src" "$dst"

    velero_patch_http_proxy "$src" "$dst"

    velero_change_storageclass "$src" "$dst"

    # Remove restic resources since they've been replaced by node agent
    kubectl delete daemonset -n "$VELERO_NAMESPACE" restic --ignore-not-found
    kubectl delete secret -n "$VELERO_NAMESPACE" velero-restic-credentials --ignore-not-found
    kubectl delete crd resticrepositories.velero.io --ignore-not-found

    # If we already migrated, or we on a new install that has the disableS3 flag set and an
    # RWX storage class is available, we need a PVC attached. When no RWX storage class is
    # available the install uses --no-default-backup-location so that KOTS can configure
    # Host Path or NFS snapshots after the installer completes.
    # Velero 1.17+ uses Kopia which does not support the Local Volume Provider.
    if ! velero_version_ge "1.17.0" && { kubernetes_resource_exists "$VELERO_NAMESPACE" pvc velero-internal-snapshots || { [ "$KOTSADM_DISABLE_S3" == "1" ] && velero_rwx_storage_class_exists; }; }; then
        velero_patch_internal_pvc_snapshots "$src" "$dst"
    fi

    # Check if we need a migration
    if velero_should_migrate_from_object_store; then
        velero_migrate_from_object_store "$src" "$dst"
    fi

    kubectl apply -k "$dst"

    kubectl label -n default --overwrite service/kubernetes velero.io/exclude-from-backup=true

    # Bail if the migration fails, preventing the original object store from being deleted
    if velero_did_migrate_from_object_store; then
        logWarn "Velero will migrate from object store to pvc"
        if ! try_5m velero_pvc_migrated ; then
            velero_pvc_migrated_debug_info
            bail "Velero migration failed"
        fi
        logSuccess "Velero migration complete"
    fi

    # Patch snapshots volumes to "Retain" in case of deletion
    if kubernetes_resource_exists "$VELERO_NAMESPACE" pvc velero-internal-snapshots; then

        local velero_pv_name
        echo "Patching internal snapshot volume Reclaim Policy to RECLAIM"
        try_1m velero_pvc_bound
        velero_pv_name=$(kubectl get pvc velero-internal-snapshots -n ${VELERO_NAMESPACE} -ojsonpath='{.spec.volumeName}')
        kubectl patch pv "$velero_pv_name" -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
    fi

    log "Waiting for velero deployment to be fully updated"
    if ! spinner_until 120 deployment_fully_updated velero velero; then
        logFail "Velero deployment failed to update"
        return 1
    fi
    logSuccess "Velero deployment updated"
}

function velero_join() {
    velero_binary
    velero_host_init
}

function velero_host_init() {
    install_nfs_utils_if_missing_common "$DIR/addons/velero/$VELERO_VERSION"
}

function velero_version_ge() {
    local target_version="$1"
    semverCompare "${VELERO_VERSION//v/}" "$target_version"
    if [ "$SEMVER_COMPARE_RESULT" != "-1" ]; then
        return 0
    fi
    return 1
}

# Returns the provider of the default BackupStorageLocation, or exits with an error if it does not exist.
function velero_bsl_provider() {
    if ! kubernetes_resource_exists "$VELERO_NAMESPACE" backupstoragelocation default; then
        return 1
    fi
    kubectl -n "$VELERO_NAMESPACE" get backupstoragelocation default -o jsonpath='{.spec.provider}'
}

# Returns 0 if the provided BackupStorageLocation provider is one of the Local Volume Provider types.
# If no provider is passed, the default BackupStorageLocation provider is used.
function velero_bsl_is_local_volume_provider() {
    local provider="${1:-}"
    if [ -z "$provider" ]; then
        return 1
    fi
    case "$provider" in
        replicated.com/hostpath|replicated.com/nfs|replicated.com/pvc)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Returns the name of the Local Volume Provider snapshot destination as it appears in the
# Admin Console, for use in messages. If no provider is given, the default
# BackupStorageLocation provider is used.
function velero_lvp_destination_name() {
    local provider="${1:-}"
    if [ -z "$provider" ]; then
        provider=$(velero_bsl_provider) || true
    fi
    case "$provider" in
        replicated.com/hostpath)
            echo "Host Path"
            ;;
        replicated.com/nfs)
            echo "Network File System (NFS)"
            ;;
        *)
            # replicated.com/pvc and an existing velero-internal-snapshots PVC are the
            # Internal Storage destination
            echo "Internal Storage"
            ;;
    esac
}

# Returns 0 if Velero in this cluster is currently using the Local Volume Provider for
# snapshots: the default BackupStorageLocation uses an LVP provider, or the
# velero-internal-snapshots PVC exists.
function velero_using_local_volume_provider() {
    local bsl_provider
    bsl_provider=$(velero_bsl_provider) || true
    if [ -n "$bsl_provider" ] && velero_bsl_is_local_volume_provider "$bsl_provider"; then
        return 0
    fi
    if kubernetes_resource_exists "$VELERO_NAMESPACE" pvc velero-internal-snapshots; then
        return 0
    fi
    return 1
}

# Returns 0 if an in-cluster S3-compatible object store (Minio or a healthy Rook Ceph RGW)
# is running and can be used as the new Velero BackupStorageLocation. This checks live
# cluster state so that it works during pre_init, before the object store add-ons have
# exported their environment variables.
function velero_object_store_available_for_migration() {
    local minio_namespace="${MINIO_NAMESPACE:-minio}"
    if kubernetes_resource_exists "$minio_namespace" deployment minio || \
        kubernetes_resource_exists "$minio_namespace" statefulset ha-minio; then
        return 0
    fi
    if kubernetes_resource_exists rook-ceph deployment rook-ceph-rgw-rook-ceph-store-a && \
        rook_rgw_check_if_is_healthy; then
        return 0
    fi
    return 1
}

# Returns 0 if the kotsadm version in the installer spec will not re-configure Velero back
# onto the Local Volume Provider after the migration.
function velero_kotsadm_version_ok() {
    if [ -z "$KOTSADM_VERSION" ]; then
        # kotsadm is not in the installer spec; nothing will re-configure velero
        return 0
    fi
    case "$KOTSADM_VERSION" in
        latest|alpha|nightly)
            # these resolve to recent builds
            return 0
            ;;
    esac
    if ! [[ "${KOTSADM_VERSION#v}" =~ ^[0-9] ]]; then
        # unknown format; assume it is not an old release
        return 0
    fi
    semverCompare "${KOTSADM_VERSION//v/}" "$VELERO_MIN_KOTSADM_VERSION"
    if [ "$SEMVER_COMPARE_RESULT" != "-1" ]; then
        return 0
    fi
    return 1
}

# Returns 0 if the Local Volume Provider -> object store migration should run during this
# upgrade: the target Velero version is 1.17+, the cluster is using the Local Volume
# Provider, S3 snapshots are not disabled, an in-cluster object store is available, and
# the kotsadm version in the spec will not re-configure Velero back onto the LVP.
function velero_should_migrate_lvp_to_object_store() {
    if ! velero_version_ge "1.17.0"; then
        return 1
    fi
    if [ "$KOTSADM_DISABLE_S3" == 1 ]; then
        return 1
    fi
    if ! velero_using_local_volume_provider; then
        return 1
    fi
    if ! velero_object_store_available_for_migration; then
        return 1
    fi
    if ! velero_kotsadm_version_ok; then
        return 1
    fi
    return 0
}

# Migrate Velero from the Local Volume Provider to the in-cluster object store so that it
# can be upgraded to 1.17+. This is a config cut-over, not a data migration: Velero 1.17+
# uses Kopia, which cannot read the restic repositories used by the LVP, so pre-upgrade
# snapshots are not restorable either way. The old snapshot data is retained on disk.
# Every step is idempotent so a failed run can simply be re-run.
function velero_migrate_lvp_to_object_store() {
    local bsl_provider
    bsl_provider=$(velero_bsl_provider) || true
    local lvp_destination
    lvp_destination=$(velero_lvp_destination_name "$bsl_provider")

    printf "\n"
    printf "Velero is using the ${lvp_destination} snapshot destination, which is not supported by Velero 1.17 and later.\n"
    printf "This upgrade will re-configure Velero to use the in-cluster object store instead.\n"
    printf "\n"
    printf "Snapshots taken before this upgrade WILL NOT BE RESTORABLE afterwards: Velero 1.17+ uses Kopia,\n"
    printf "which cannot read the existing restic repositories, regardless of this migration.\n"
    printf "The existing snapshot data will be retained on disk in case manual recovery is needed.\n"
    printf "\n"
    printf "Continue?"
    if ! confirmN; then
        bail "Local Volume Provider migration declined. Re-run the installer and accept the prompt to migrate, run with the 'yes' flag to accept automatically, or pin Velero to a version earlier than 1.17. Manual migration steps: https://community.replicated.com/t/upgrade-guide-velero-1-16-to-1-17-on-kurl-kots-with-lvp-snapshots/1647"
    fi

    local backup_dir="$DIR/kustomize/velero/lvp-migration-backup"
    mkdir -p "$backup_dir"

    # save the current resources for manual recovery and auditing
    if kubernetes_resource_exists "$VELERO_NAMESPACE" backupstoragelocation default; then
        kubectl -n "$VELERO_NAMESPACE" get backupstoragelocation default -o yaml > "$backup_dir/backupstoragelocation-default.yaml"
        if [ "$bsl_provider" != "replicated.com/pvc" ]; then
            # hostpath and nfs destinations keep their data outside the cluster; the path
            # is recorded in the saved BackupStorageLocation
            logWarn "Existing snapshot data for the ${lvp_destination} destination is retained at its configured location; see $backup_dir/backupstoragelocation-default.yaml"
        fi
    fi
    if kubernetes_resource_exists "$VELERO_NAMESPACE" pvc velero-internal-snapshots; then
        kubectl -n "$VELERO_NAMESPACE" get pvc velero-internal-snapshots -o yaml > "$backup_dir/pvc-velero-internal-snapshots.yaml"
    fi

    # delete the velero workloads and storage location so that they are cleanly re-created
    # by the install below; this also avoids the node-agent failing on stale repository data
    kubectl delete deployment -n "$VELERO_NAMESPACE" velero --ignore-not-found
    kubectl delete daemonset -n "$VELERO_NAMESPACE" node-agent --ignore-not-found
    kubectl delete backupstoragelocation -n "$VELERO_NAMESPACE" default --ignore-not-found
    # only delete the repository custom resources when their CRD exists: kubectl fails with
    # "the server doesn't have a resource type" for missing kinds even with --ignore-not-found
    if kubectl get crd backuprepositories.velero.io &>/dev/null; then
        kubectl -n "$VELERO_NAMESPACE" delete backuprepository --all --ignore-not-found
    fi
    if kubectl get crd resticrepositories.velero.io &>/dev/null; then
        kubectl -n "$VELERO_NAMESPACE" delete resticrepository --all --ignore-not-found
    fi

    # retain the old snapshot data on disk and remove the PVC; finalizers may need to be
    # removed if the LVP provisioner is no longer running
    if kubernetes_resource_exists "$VELERO_NAMESPACE" pvc velero-internal-snapshots; then
        local velero_pv_name
        velero_pv_name=$(kubectl -n "$VELERO_NAMESPACE" get pvc velero-internal-snapshots -ojsonpath='{.spec.volumeName}')
        if [ -n "$velero_pv_name" ]; then
            echo "Patching internal snapshot volume $velero_pv_name Reclaim Policy to Retain"
            kubectl patch pv "$velero_pv_name" -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
            kubectl get pv "$velero_pv_name" -o yaml > "$backup_dir/pv-${velero_pv_name}.yaml"
            logSuccess "Old snapshot data retained in volume $velero_pv_name"
        fi
        kubectl -n "$VELERO_NAMESPACE" patch pvc velero-internal-snapshots -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
        kubectl -n "$VELERO_NAMESPACE" delete pvc velero-internal-snapshots --ignore-not-found --timeout=2m || true
    fi

    logSuccess "Local Volume Provider migration complete; Velero will be re-configured to use the in-cluster object store"
}

function velero_install() {
    local src="$1"
    local dst="$2"

    # Pre-apply CRDs since kustomize reorders resources. Grep to strip out sailboat emoji.
    "$src"/assets/velero-v"${VELERO_VERSION}"-linux-amd64/velero install --crds-only | grep -v 'Velero is installed'

    local nodeAgentArgs=""
    if [ "$VELERO_DISABLE_RESTIC" != "1" ]; then
        if velero_version_ge "1.17.0"; then
            nodeAgentArgs="--use-node-agent"
        elif velero_version_ge "1.10.0"; then
            nodeAgentArgs="--use-node-agent --uploader-type=restic"
        else
            nodeAgentArgs="--use-restic"
        fi
    fi

    # detect if we need to use object store or pvc
    local bslArgs="--no-default-backup-location"
    if ! kubernetes_resource_exists "$VELERO_NAMESPACE" backupstoragelocation default; then

        # Only use the PVC backup location for new installs where disableS3 is set to TRUE and
        # there is a RWX storage class available (rook-cephfs or longhorn). Velero 1.17+ does not
        # support the Local Volume Provider, so this path is only used for older versions.
        if ! velero_version_ge "1.17.0" && [ "$KOTSADM_DISABLE_S3" == 1 ] && velero_rwx_storage_class_exists ; then
            bslArgs="--provider replicated.com/pvc --bucket velero-internal-snapshots --backup-location-config storageSize=${VELERO_PVC_SIZE},resticRepoPrefix=/var/velero-local-volume-provider/velero-internal-snapshots/restic"
        elif object_store_exists; then
            local ip=$($DIR/bin/kurl netutil format-ip-address $OBJECT_STORE_CLUSTER_IP)
            bslArgs="--provider aws --bucket $VELERO_LOCAL_BUCKET --backup-location-config region=us-east-1,s3Url=${OBJECT_STORE_CLUSTER_HOST},publicUrl=http://${ip},s3ForcePathStyle=true"
        fi
    fi

    # we need a secret file if it's already set for some other provider, OR
    # If we have object storage AND are NOT actively opting out of the existing functionality
    local secretArgs="--no-secret"
    if kubernetes_resource_exists "$VELERO_NAMESPACE" secret cloud-credentials || { object_store_exists && ! [ "$KOTSADM_DISABLE_S3" == 1 ]; }; then
        velero_credentials
        secretArgs="--secret-file velero-credentials"
    fi

    local plugins="velero/velero-plugin-for-aws:v1.13.2,velero/velero-plugin-for-gcp:v1.13.2,velero/velero-plugin-for-microsoft-azure:v1.13.2,${KURL_UTIL_IMAGE}"
    if ! velero_version_ge "1.17.0"; then
        plugins="$plugins,replicated/local-volume-provider:0.6.10"
    fi

    "$src"/assets/velero-v"${VELERO_VERSION}"-linux-amd64/velero install \
        $nodeAgentArgs \
        $bslArgs \
        $secretArgs \
        --namespace $VELERO_NAMESPACE \
        --plugins "$plugins" \
        --use-volume-snapshots=false \
        --dry-run -o yaml > "$dst/velero.yaml"

    # Remove the restic uploader warning from the beginning of velero.yaml
    sed -i '1{/Uploader '\''restic'\'' is deprecated/d;}' "$dst/velero.yaml"

    rm -f velero-credentials
}

# This runs when re-applying the same version to a cluster
function velero_already_applied() {
    local src="$DIR/addons/velero/$VELERO_VERSION"
    local dst="$DIR/kustomize/velero"

    # If the Local Volume Provider needs to be migrated to the object store, the install
    # must be fully reconstructed because the migration deletes the velero deployment and
    # BackupStorageLocation
    if velero_should_migrate_lvp_to_object_store; then
        velero_migrate_lvp_to_object_store

        render_yaml_file "$src/tmpl-kustomization.yaml" > "$dst/kustomization.yaml"

        determine_velero_pvc_size

        velero_binary
        velero_install "$src" "$dst"
        velero_patch_node_agent_privilege "$src" "$dst"
        velero_patch_args "$src" "$dst"
        velero_kotsadm_restore_config "$src" "$dst"
        velero_patch_http_proxy "$src" "$dst"
    fi

    # If we need to migrate, we're going to need to basically reconstruct the original install
    # underneath the migration
    if velero_should_migrate_from_object_store; then

        render_yaml_file "$src/tmpl-kustomization.yaml" > "$dst/kustomization.yaml"

        determine_velero_pvc_size

        velero_binary
        velero_install "$src" "$dst"
        velero_patch_node_agent_privilege "$src" "$dst"
        velero_patch_args "$src" "$dst"
        velero_kotsadm_restore_config "$src" "$dst"
        velero_patch_internal_pvc_snapshots "$src" "$dst"
        velero_patch_http_proxy "$src" "$dst"
        velero_migrate_from_object_store "$src" "$dst"
    fi

    # If we didn't need to migrate, reset the kustomization file and only apply the configmap
    # This function will create a new, blank kustomization file.
    velero_change_storageclass "$src" "$dst"

    # In the case this is a rook re-apply, no changes might be required
    if [ -f "$dst/kustomization.yaml" ]; then
        kubectl apply -k "$dst"
    fi

    # Bail if the migration fails, preventing the original object store from being deleted
    if velero_did_migrate_from_object_store; then
        logWarn "Velero will migrate from object store to pvc"
        if ! try_5m velero_pvc_migrated ; then
            velero_pvc_migrated_debug_info
            bail "Velero migration failed"
        fi
        logSuccess "Velero migration complete"
    fi

    # Patch snapshots volumes to "Retain" in case of deletion
    if kubernetes_resource_exists "$VELERO_NAMESPACE" pvc velero-internal-snapshots && velero_should_migrate_from_object_store; then
        local velero_pv_name
        echo "Patching internal snapshot volume Reclaim Policy to RECLAIM"
        try_1m velero_pvc_bound
        velero_pv_name=$(kubectl get pvc velero-internal-snapshots -n ${VELERO_NAMESPACE} -ojsonpath='{.spec.volumeName}')
        kubectl patch pv "$velero_pv_name" -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
    fi
}

# The --secret-file flag should be used so that the generated velero deployment uses the
# cloud-credentials secret. Use the contents of that secret if it exists to avoid overwriting
# any changes.
function velero_credentials() {
    if kubernetes_resource_exists "$VELERO_NAMESPACE" secret cloud-credentials; then
        kubectl -n velero get secret cloud-credentials -ojsonpath='{ .data.cloud }' | base64 -d > velero-credentials
        return 0
    fi

    if [ -n "$OBJECT_STORE_CLUSTER_IP" ]; then
        try_1m object_store_create_bucket "$VELERO_LOCAL_BUCKET"
    fi

    cat >velero-credentials <<EOF
[default]
aws_access_key_id=$OBJECT_STORE_ACCESS_KEY
aws_secret_access_key=$OBJECT_STORE_SECRET_KEY
EOF
}

function velero_patch_node_agent_privilege() {
    local src="$1"
    local dst="$2"

    if [ "${VELERO_DISABLE_RESTIC}" = "1" ]; then
        return 0
    fi

    if [ "${VELERO_RESTIC_REQUIRES_PRIVILEGED}" = "1" ]; then
        render_yaml_file "$src/node-agent-daemonset-privileged.yaml" > "$dst/node-agent-daemonset-privileged.yaml"
        insert_patches_strategic_merge "$dst/kustomization.yaml" node-agent-daemonset-privileged.yaml
    fi
}

function velero_patch_args() {
    local src="$1"
    local dst="$2"

    # if the user has specified any additional velero server flags, add them to the velero deployment
    if [ -n "$VELERO_SERVER_FLAGS" ]; then
        # iterate over the flags in reverse order since they are prepended to the list of kustomize patches
        IFS=',' read -ra flags <<< "$VELERO_SERVER_FLAGS"
        for ((i=${#flags[@]}-1; i>=0; i--)); do
            velero_insert_arg "${flags[i]}" "$dst/kustomization.yaml"
        done
    fi

    # if the user has not disabled file-system backups and specified a timeout, add it to the velero deployment
    if [ "${VELERO_DISABLE_RESTIC}" != "1" ] && [ -n "$VELERO_RESTIC_TIMEOUT" ]; then
        velero_insert_arg "--fs-backup-timeout=$VELERO_RESTIC_TIMEOUT" "$dst/kustomization.yaml"
    fi
}

function velero_insert_arg() {
    local arg="$1"
    local kustomization_file="$2"

    local patch_file="velero-args-json-patch_$arg.yaml"
    cat > "$dst/$patch_file" <<EOF
- op: add
  path: /spec/template/spec/containers/0/args/-
  value: $arg
EOF

    insert_patches_json_6902 $kustomization_file $patch_file apps v1 Deployment velero ${VELERO_NAMESPACE}
}

function velero_binary() {
    local src="$DIR/addons/velero/$VELERO_VERSION"

    if ! kubernetes_is_master; then
        return 0
    fi

    if [ ! -f "$src/assets/velero.tar.gz" ] && [ "$AIRGAP" != "1" ]; then
        mkdir -p "$src/assets"
        curl -L "https://github.com/vmware-tanzu/velero/releases/download/v${VELERO_VERSION}/velero-v${VELERO_VERSION}-linux-amd64.tar.gz" > "$src/assets/velero.tar.gz"
    fi

    pushd "$src/assets" || exit 1
    tar xf "velero.tar.gz"
    if [ "$VELERO_DISABLE_CLI" != "1" ]; then
        cp velero-v${VELERO_VERSION}-linux-amd64/velero /usr/local/bin/velero
    fi
    popd || exit 1
}

function velero_kotsadm_restore_config() {
    local src="$1"
    local dst="$2"

    render_yaml_file "$src/tmpl-kotsadm-restore-config.yaml" > "$dst/kotsadm-restore-config.yaml"
    insert_resources "$dst/kustomization.yaml" kotsadm-restore-config.yaml
}

function velero_patch_http_proxy() {
    local src="$1"
    local dst="$2"
    if [ -n "$PROXY_ADDRESS" ] || [ -n "$PROXY_HTTPS_ADDRESS" ]; then
        if [ -z "$PROXY_HTTPS_ADDRESS" ]; then
            PROXY_HTTPS_ADDRESS="$PROXY_ADDRESS"
        fi
        render_yaml_file_2 "$src/tmpl-velero-deployment-proxy.yaml" > "$dst/velero-deployment-proxy.yaml"
        insert_patches_strategic_merge "$dst/kustomization.yaml" velero-deployment-proxy.yaml
        if [ "$VELERO_DISABLE_RESTIC" != "1" ]; then
            render_yaml_file_2 "$src/tmpl-node-agent-daemonset-proxy.yaml" > "$dst/node-agent-daemonset-proxy.yaml"
            insert_patches_strategic_merge "$dst/kustomization.yaml" node-agent-daemonset-proxy.yaml
        fi
    fi
}

# If this cluster is used to restore a snapshot taken on a cluster where Rook or OpenEBS was the
# default storage provisioner, the storageClassName on PVCs will need to be changed from "default"
# to "longhorn" by velero
# https://velero.io/docs/v1.6/restore-reference/#changing-pvpvc-storage-classes
function velero_change_storageclass() {
    local src="$1"
    local dst="$2"

    if kubectl get sc longhorn &> /dev/null && \
    [ "$(kubectl get sc longhorn -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}')" = "true" ]; then

        # when re-applying the same velero version, this might not exist.
        if [ ! -f "$dst/kustomization.yaml" ]; then
            cat > "$dst/kustomization.yaml" <<EOF
namespace: ${VELERO_NAMESPACE}

resources:
EOF
        fi

        render_yaml_file "$src/tmpl-change-storageclass.yaml" > "$dst/change-storageclass.yaml"
        insert_resources "$dst/kustomization.yaml" change-storageclass.yaml

    fi
}

function velero_should_migrate_from_object_store() {
    # If KOTSADM_DISABLE_S3 is set, force the migration
    if [ "$KOTSADM_DISABLE_S3" != 1 ]; then
        return 1
    fi

    # if the PVC already exists, we've already migrated
    if kubernetes_resource_exists "${VELERO_NAMESPACE}" pvc velero-internal-snapshots; then
        return 1
    fi

    # if an object store isn't installed don't migrate
    # TODO (dans): this doeesn't support minio in a non-standard namespace
    if (! kubernetes_resource_exists rook-ceph deployment rook-ceph-rgw-rook-ceph-store-a) && (! kubernetes_resource_exists minio deployment minio); then
        return 1
    fi

    # If there isn't a cloud-credentials, this isn't an existing install or it isn't using object storage; there is nothing to migrate.
    if ! kubernetes_resource_exists "$VELERO_NAMESPACE" secret cloud-credentials; then
        return 1
    fi

    return 0
}

function velero_did_migrate_from_object_store() {

    # If KOTSADM_DISABLE_S3 is set, force the migration
    if [ -f "$DIR/kustomize/velero/kustomization.yaml" ] && cat "$DIR/kustomize/velero/kustomization.yaml" | grep -q "s3-migration-deployment-patch.yaml"; then
        return 0
    fi
    return 1
}

function velero_migrate_from_object_store() {
    local src="$1"
    local dst="$2"

    export VELERO_S3_HOST=
    export VELERO_S3_ACCESS_KEY_ID=
    export VELERO_S3_ACCESS_KEY_SECRET=
    if kubernetes_resource_exists rook-ceph deployment rook-ceph-rgw-rook-ceph-store-a; then
        echo "Previous installation of Rook Ceph detected."
        VELERO_S3_HOST="rook-ceph-rgw-rook-ceph-store.rook-ceph"
        VELERO_S3_ACCESS_KEY_ID=$(kubectl -n rook-ceph get secret rook-ceph-object-user-rook-ceph-store-kurl -o yaml | grep AccessKey | head -1 | awk '{print $2}' | base64 --decode)
        VELERO_S3_ACCESS_KEY_SECRET=$(kubectl -n rook-ceph get secret rook-ceph-object-user-rook-ceph-store-kurl -o yaml | grep SecretKey | head -1 | awk '{print $2}' | base64 --decode)
    else
        echo "Previous installation of Minio detected."
        VELERO_S3_HOST="minio.minio"
        VELERO_S3_ACCESS_KEY_ID=$(kubectl -n minio get secret minio-credentials -ojsonpath='{ .data.MINIO_ACCESS_KEY }' | base64 --decode)
        VELERO_S3_ACCESS_KEY_SECRET=$(kubectl -n minio get secret minio-credentials -ojsonpath='{ .data.MINIO_SECRET_KEY }' | base64 --decode)
    fi

    # TODO (dans): figure out if there is enough space create a new volume with all the snapshot data

    # create secret for migration init container to pull from object store
    render_yaml_file "$src/tmpl-s3-migration-secret.yaml" > "$dst/s3-migration-secret.yaml"
    insert_resources "$dst/kustomization.yaml" s3-migration-secret.yaml

    # create configmap that holds the migration script
    cp "$src/s3-migration-configmap.yaml" "$dst/s3-migration-configmap.yaml"
    insert_resources "$dst/kustomization.yaml" s3-migration-configmap.yaml

    # add patch to add init container for migration
    render_yaml_file "$src/tmpl-s3-migration-deployment-patch.yaml" > "$dst/s3-migration-deployment-patch.yaml"
    insert_patches_strategic_merge "$dst/kustomization.yaml" s3-migration-deployment-patch.yaml

    # update the BackupstorageLocation
    render_yaml_file "$src/tmpl-s3-migration-bsl.yaml" > "$dst/s3-migration-bsl.yaml"
    insert_resources "$dst/kustomization.yaml" s3-migration-bsl.yaml
}

# Returns 0 if a storage class that supports RWX volumes (rook-cephfs or longhorn), which
# is required by the PVC-based Internal Storage destination, is present in the cluster.
function velero_rwx_storage_class_exists() {
    kubectl get storageclass 2>/dev/null | grep -q "longhorn" || kubectl get storageclass 2>/dev/null | grep -q "rook-cephfs"
}

# add patches for the velero and node-agent to the current kustomization file that setup the PVC setup like the
# velero LVP plugin requires
function velero_patch_internal_pvc_snapshots() {
    local src="$1"
    local dst="$2"

    # If we are migrating from Rook to Longhorn, longhorn is not yet the default storage class.
    export VELERO_PVC_STORAGE_CLASS="rook-cephfs" # this is the rook-ceph storage class for RWX access
    if [ -n "$LONGHORN_VERSION" ]; then
        export VELERO_PVC_STORAGE_CLASS="longhorn"
    fi

    # create the PVC if it does not already exist
    if (! kubernetes_resource_exists "$VELERO_NAMESPACE" pvc velero-internal-snapshots ) ; then
          render_yaml_file "$src/tmpl-internal-snaps-pvc.yaml" > "$dst/internal-snaps-pvc.yaml"
          insert_resources "$dst/kustomization.yaml" internal-snaps-pvc.yaml
    fi

    # add patch to add the pvc in the correct location for the velero deployment
    render_yaml_file "$src/tmpl-internal-snaps-deployment-patch.yaml" > "$dst/internal-snaps-deployment-patch.yaml"
    insert_patches_strategic_merge "$dst/kustomization.yaml" internal-snaps-deployment-patch.yaml

    # add patch to add the pvc in the correct location for the node-agent daemonset
    render_yaml_file "$src/tmpl-internal-snaps-ds-patch.yaml" > "$dst/internal-snaps-ds-patch.yaml"
    insert_patches_strategic_merge "$dst/kustomization.yaml" internal-snaps-ds-patch.yaml

}

function velero_pvc_bound() {
    kubectl get pvc velero-internal-snapshots -n ${VELERO_NAMESPACE} -ojsonpath='{.status.phase}' | grep -q "Bound"
}

# if the PVC size has already been set we should not reduce it
function determine_velero_pvc_size() {
    local velero_pvc_size="50Gi"
    if kubernetes_resource_exists "${VELERO_NAMESPACE}" pvc velero-internal-snapshots; then
        velero_pvc_size=$( kubectl get pvc -n "${VELERO_NAMESPACE}" velero-internal-snapshots -o jsonpath='{.spec.resources.requests.storage}')
    fi

    export VELERO_PVC_SIZE=$velero_pvc_size
}

function velero_pvc_migrated() {
    local velero_pod=
    velero_pod=$(kubectl get pods -n velero -l component=velero -o jsonpath='{.items[?(@.spec.containers[0].name=="velero")].metadata.name}')
    if kubectl -n velero logs "$velero_pod" -c migrate-s3 | grep -q "migration ran successfully" &>/dev/null; then
        return 0
    fi
    if kubectl -n velero logs "$velero_pod" -c migrate-s3 | grep -q "migration has already run" &>/dev/null; then
        return 0
    fi
    return 1
}

function velero_pvc_migrated_debug_info() {
    kubectl get pods -n velero -l component=velero
    local velero_pod=
    velero_pod=$(kubectl get pods -n velero -l component=velero -o jsonpath='{.items[?(@.spec.containers[0].name=="velero")].metadata.name}')
    kubectl -n velero logs "$velero_pod" -c migrate-s3
}
