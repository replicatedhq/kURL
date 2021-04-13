
function velero_pre_init() {
    if [ -z "$VELERO_NAMESPACE" ]; then
        VELERO_NAMESPACE=velero
    fi
    if [ -z "$VELERO_LOCAL_BUCKET" ]; then
        VELERO_LOCAL_BUCKET=velero
    fi
}

function velero() {
    local src="$DIR/addons/velero/$VELERO_VERSION"
    local dst="$DIR/kustomize/velero"

    cp "$src/kustomization.yaml" "$dst/"

    velero_binary

    velero_install "$src" "$dst"

    velero_patch_restic_privilege "$src" "$dst"

    kubectl apply -k "$dst"

    kubectl label -n default --overwrite service/kubernetes velero.io/exclude-from-backup=true
}

function velero_join() {
    velero_binary
}

function velero_install() {
    local src="$1"
    local dst="$2"

    # Pre-apply CRDs since kustomize reorders resources. Grep to strip out sailboat emoji.
    $src/assets/velero-v${VELERO_VERSION}-linux-amd64/velero install --crds-only | grep -v 'Velero is installed'

    local resticArg="--use-restic"
    if [ "$VELERO_DISABLE_RESTIC" = "1" ]; then
        resticArg=""
    fi

    local bslArgs="--no-default-backup-location"
    if ! kubernetes_resource_exists "$VELERO_NAMESPACE" backupstoragelocation default; then
        bslArgs="--provider aws --bucket $VELERO_LOCAL_BUCKET --backup-location-config region=us-east-1,s3Url=${OBJECT_STORE_CLUSTER_HOST},publicUrl=http://${OBJECT_STORE_CLUSTER_IP},s3ForcePathStyle=true"
    fi

    velero_credentials

    $src/assets/velero-v${VELERO_VERSION}-linux-amd64/velero install \
        $resticArg \
        $bslArgs \
        --plugins velero/velero-plugin-for-aws:v1.2.0,velero/velero-plugin-for-gcp:v1.2.0,velero/velero-plugin-for-microsoft-azure:v1.2.0 \
        --secret-file velero-credentials \
        --use-volume-snapshots=false \
        --namespace $VELERO_NAMESPACE \
        --dry-run -o yaml > "$dst/velero.yaml"

    rm velero-credentials
}

# The --secret-file flag must always be used so that the generated velero deployment uses the
# cloud-credentials secret. Use the contents of that secret if it exists to avoid overwriting
# any changes. Else if a local object store (Ceph/Minio) is configured, use its credentials.
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

function velero_patch_restic_privilege() {
    local src="$1"
    local dst="$2"

    if [ "${VELERO_DISABLE_RESTIC}" = "1" ]; then
        return 0
    fi

    if [ "${K8S_DISTRO}" = "rke2" ] || [ "${VELERO_RESTIC_REQUIRES_PRIVILEGED}" = "1" ]; then
        render_yaml_file "$src/restic-daemonset-privileged.yaml" > "$dst/restic-daemonset-privileged.yaml"
        insert_patches_strategic_merge "$dst/kustomization.yaml" restic-daemonset-privileged.yaml
    fi
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

    pushd "$src/assets"
    tar xf "velero.tar.gz"
    if [ "$VELERO_DISABLE_CLI" != "1" ]; then
        cp velero-v${VELERO_VERSION}-linux-amd64/velero /usr/local/bin/velero
    fi
    popd
}
