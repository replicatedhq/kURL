
function velero_pre_init() {
    if [ -z "$VELERO_NAMESPACE" ]; then
        VELERO_NAMESPACE=velero
    fi
    if [ -z "$VELERO_LOCAL_BUCKET" ]; then
        VELERO_LOCAL_BUCKET=velero
    fi
}

function velero() {
    local src="$DIR/addons/velero/1.2.0"
    local dst="$DIR/kustomize/velero"

    cp -r "$src/crd" "$dst/"
    kubectl apply -k "$dst/crd"

    cp "$src/deployment.yaml" \
        "$src/rbac.yaml" \
        "$src/service.yaml" \
        "$dst/"

    render_yaml_file "$src/tmpl-kustomization.yaml" > "$dst/kustomization.yaml"
    render_yaml_file "$src/tmpl-namespace.yaml" > "$dst/namespace.yaml"

    kubectl create namespace "$VELERO_NAMESPACE" 2>/dev/null || true

    if [ "$VELERO_DISABLE_RESTIC" != "1" ]; then
        cp "$src/restic-daemonset.yaml" "$dst/"
        insert_resources "$dst/kustomization.yaml" restic-daemonset.yaml
    fi

    velero_local_rgw_store

    kubectl apply -k "$dst"

    velero_binary
}

function velero_join() {
    velero_binary
}

function velero_binary() {
    if [ "$VELERO_DISABLE_CLI" = "1" ]; then
        return 0
    fi
    if ! kubernetes_is_master; then
        return 0
    fi
    local id=$(docker create velero/velero:v1.2.0)
    docker cp ${id}:/velero velero
    docker rm ${id}
    chmod a+x velero
    mv velero /usr/local/bin/velero
}

function velero_local_rgw_store() {
    local src="$DIR/addons/velero/1.2.0"
    local dst="$DIR/kustomize/velero"

    local backendCount=$(kubectl -n "$VELERO_NAMESPACE" get backupstoragelocations --no-headers | wc -l)
    if [ "$backendCount" -gt 0 ]; then
        echo "A backend storage location already exists. Skipping creation of new local RGW backend for Velero"
        return 0
    fi

    if [ -z "$OBJECT_STORE_ACCESS_KEY" ] || [ -z "$OBJECT_STORE_SECRET_KEY" ] || [ -z "$OBJECT_STORE_CLUSTER_IP" ]; then
        echo "Local RGW store not configured. Skipping creation of new local RWG backend for Velero"
        return 0
    fi

    try_1m object_store_create_bucket "$VELERO_LOCAL_BUCKET"

    render_yaml_file "$src/tmpl-backupstoragelocation.yaml" > "$dst/backupstoragelocation.yaml"
    insert_resources "$dst/kustomization.yaml" backupstoragelocation.yaml
}
