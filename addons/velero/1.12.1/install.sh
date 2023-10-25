# shellcheck disable=SC2148
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

    # If someone uses OpenEBS as their primary CSI provider, bail because it doesn't support RWX volumes
    if [ -z "$ROOK_VERSION" ] && [ -z "$LONGHORN_VERSION" ] && [ "$KOTSADM_DISABLE_S3" == 1 ]; then
        bail "Only Rook and Longhorn are supported for Velero Internal backup storage."
    fi

    velero_host_init
}

# runs on first install, and on version upgrades only
function velero() {
    local src="$DIR/addons/velero/$VELERO_VERSION"
    local dst="$DIR/kustomize/velero"

    render_yaml_file "$src/tmpl-kustomization.yaml" > "$dst/kustomization.yaml"

    velero_binary

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

    # If we already migrated, or we on a new install that has the disableS3 flag set, we need a PVC attached
    if kubernetes_resource_exists "$VELERO_NAMESPACE" pvc velero-internal-snapshots || [ "$KOTSADM_DISABLE_S3" == "1" ]; then
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

    spinner_until 120 deployment_fully_updated velero velero
}

function velero_join() {
    velero_binary
    velero_host_init
}

function velero_host_init() {
    velero_install_nfs_utils_if_missing
}

function velero_install_nfs_utils_if_missing() {
    local src="$DIR/addons/velero/$VELERO_VERSION"

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

function velero_install() {
    local src="$1"
    local dst="$2"

    # Pre-apply CRDs since kustomize reorders resources. Grep to strip out sailboat emoji.
    "$src"/assets/velero-v"${VELERO_VERSION}"-linux-amd64/velero install --crds-only | grep -v 'Velero is installed'

    local nodeAgentArgs="--use-node-agent --uploader-type=restic"
    if [ "$VELERO_DISABLE_RESTIC" = "1" ]; then
        nodeAgentArgs=""
    fi

    # detect if we need to use object store or pvc
    local bslArgs="--no-default-backup-location"
    if ! kubernetes_resource_exists "$VELERO_NAMESPACE" backupstoragelocation default; then

        # Only use the PVC backup location for new installs where disableS3 is set to TRUE and
        # there is a RWX storage class available (rook-cephfs or longhorn)
        if [ "$KOTSADM_DISABLE_S3" == 1 ] && { kubectl get storageclass | grep "longhorn" || kubectl get storageclass | grep "rook-cephfs" ; } ; then
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

    "$src"/assets/velero-v"${VELERO_VERSION}"-linux-amd64/velero install \
        $nodeAgentArgs \
        $bslArgs \
        $secretArgs \
        --namespace $VELERO_NAMESPACE \
        --plugins velero/velero-plugin-for-aws:v1.8.1,velero/velero-plugin-for-gcp:v1.8.1,velero/velero-plugin-for-microsoft-azure:v1.8.1,replicated/local-volume-provider:v0.5.4,"$KURL_UTIL_IMAGE" \
        --use-volume-snapshots=false \
        --dry-run -o yaml > "$dst/velero.yaml"

    rm -f velero-credentials
}

# This runs when re-applying the same version to a cluster
function velero_already_applied() {
    local src="$DIR/addons/velero/$VELERO_VERSION"
    local dst="$DIR/kustomize/velero"

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

    # if the user has not disabled restic and specified a restic timeout, add it to the velero deployment
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
