
function velero_pre_init() {
    if [ -z "$VELERO_NAMESPACE" ]; then
        VELERO_NAMESPACE=velero
    fi
    if [ -z "$VELERO_LOCAL_BUCKET" ]; then
        VELERO_LOCAL_BUCKET=velero
    fi

    velero_host_init
}

function velero() {
    local src="$DIR/addons/velero/1.5.1"
    local dst="$DIR/kustomize/velero"

    cp -r "$src/crd" "$dst/"
    kubectl apply -k "$dst/crd"

    cp "$src/deployment.yaml" \
        "$src/rbac.yaml" \
        "$dst/"

    render_yaml_file "$src/tmpl-kustomization.yaml" > "$dst/kustomization.yaml"
    render_yaml_file "$src/tmpl-namespace.yaml" > "$dst/namespace.yaml"

    velero_kotsadm_restore_config "$src" "$dst"

    velero_patch_http_proxy "$src" "$dst"

    velero_change_storageclass "$src" "$dst"

    kubectl create namespace "$VELERO_NAMESPACE" 2>/dev/null || true

    if [ "${K8S_DISTRO}" = "rke2" ]; then
        VELERO_RESTIC_REQUIRES_PRIVILEGED=1
    fi

    if [ "$VELERO_DISABLE_RESTIC" != "1" ]; then
        cp "$src/restic-daemonset.yaml" "$dst/"
        insert_resources "$dst/kustomization.yaml" restic-daemonset.yaml

        if [ "${VELERO_RESTIC_REQUIRES_PRIVILEGED}" = "1" ]; then
            cp "$src/restic-daemonset-privileged.yaml" "$dst/"
            insert_patches_strategic_merge "$dst/kustomization.yaml" restic-daemonset-privileged.yaml
        fi
    fi

    velero_patch_args "$src" "$dst"

    velero_kotsadm_local_backend

    kubectl apply -k "$dst"

    velero_binary

    /usr/local/bin/velero plugin add replicated/local-volume-provider:v0.1.0
    /usr/local/bin/velero plugin add $KURL_UTIL_IMAGE

    kubectl label -n default --overwrite service/kubernetes velero.io/exclude-from-backup=true
}

function velero_join() {
    velero_binary
    velero_host_init
}

function velero_host_init() {
    install_nfs_utils_if_missing_common "$DIR/addons/velero/$VELERO_VERSION"
}

function velero_already_applied() {
    local src="$DIR/addons/velero/$VELERO_VERSION"
    local dst="$DIR/kustomize/velero"

    velero_change_storageclass "$src" "$dst" true

    # This should only be applying the configmap if required
    if compgen -G "$dst/*.yaml" > /dev/null; then
        kubectl apply -f "$dst"
    fi
}

function velero_binary() {
    local src="$DIR/addons/velero/1.5.1"

    if [ "$VELERO_DISABLE_CLI" = "1" ]; then
        return 0
    fi
    if ! kubernetes_is_master; then
        return 0
    fi

    if [ ! -f "$src/assets/velero.tar.gz" ] && [ "$AIRGAP" != "1" ]; then
        mkdir -p "$src/assets"
        curl -L "https://github.com/vmware-tanzu/velero/releases/download/v1.5.1/velero-v1.5.1-linux-amd64.tar.gz" > "$src/assets/velero.tar.gz"
    fi

    pushd "$src/assets"
    tar xf "velero.tar.gz"
    mv velero-v1.5.1-linux-amd64/velero /usr/local/bin/velero
    popd
}

function velero_kotsadm_local_backend() {
    local src="$DIR/addons/velero/1.5.1"
    local dst="$DIR/kustomize/velero"

    if kubernetes_resource_exists "$VELERO_NAMESPACE" backupstoragelocation default \
        || kubernetes_resource_exists "$VELERO_NAMESPACE" secret aws-credentials; then
        echo "A backend storage location already exists. Skipping creation of new local backend for Velero"
        return 0
    fi

    if [ -z "$OBJECT_STORE_ACCESS_KEY" ] || [ -z "$OBJECT_STORE_SECRET_KEY" ] || [ -z "$OBJECT_STORE_CLUSTER_IP" ]; then
        echo "Local object store not configured. Skipping creation of new local backend for Velero"
        return 0
    fi

    try_1m object_store_create_bucket "$VELERO_LOCAL_BUCKET"

    render_yaml_file "$src/tmpl-kotsadm-local-backend.yaml" > "$dst/kotsadm-local-backend.yaml"
    insert_resources "$dst/kustomization.yaml" kotsadm-local-backend.yaml
}

function velero_patch_args() {
    local src="$1"
    local dst="$2"

    if [ "${VELERO_DISABLE_RESTIC}" = "1" ] || [ -z "${VELERO_RESTIC_TIMEOUT}" ]; then
        return 0
    fi

    render_yaml_file "$src/velero-args-json-patch.yaml" > "$dst/velero-args-json-patch.yaml"
    insert_patches_json_6902 "$dst/kustomization.yaml" velero-args-json-patch.yaml apps v1 Deployment velero ${VELERO_NAMESPACE}
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

    if [ -n "$PROXY_ADDRESS" ]; then
        render_yaml_file "$src/tmpl-velero-deployment-proxy.yaml" > "$dst/velero-deployment-proxy.yaml"
        insert_patches_strategic_merge "$dst/kustomization.yaml" velero-deployment-proxy.yaml
    fi

    if [ -n "$PROXY_ADDRESS" ] && [ "$VELERO_DISABLE_RESTIC" != "1" ]; then
        render_yaml_file "$src/tmpl-restic-daemonset-proxy.yaml" > "$dst/restic-daemonset-proxy.yaml"
        insert_patches_strategic_merge "$dst/kustomization.yaml" restic-daemonset-proxy.yaml
    fi
}

# If this cluster is used to restore a snapshot taken on a cluster where Rook or OpenEBS was the 
# default storage provisioner, the storageClassName on PVCs will need to be changed from "default"
# to "longhorn" by velero
# https://velero.io/docs/v1.6/restore-reference/#changing-pvpvc-storage-classes
function velero_change_storageclass() {
    local src="$1"
    local dst="$2"
    local disable_kustomization="$3"

    if kubectl get sc longhorn &> /dev/null && \
    [ "$(kubectl get sc longhorn -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}')" = "true" ]; then
        render_yaml_file "$src/tmpl-change-storageclass.yaml" > "$dst/change-storageclass.yaml"
        if [ -z "$disable_kustomization" ]; then
            insert_resources "$dst/kustomization.yaml" change-storageclass.yaml
        fi
    fi
}
