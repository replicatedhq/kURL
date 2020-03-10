
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

    velero_kotsadm_local_backend

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

function velero_kotsadm_local_backend() {
    local src="$DIR/addons/velero/1.2.0"
    local dst="$DIR/kustomize/velero"

    if [ -z "$KOTSADM_VERSION" ]; then
        return 0
    fi

    if kubernetes_has_resource "$VELERO_NAMESPACE" backupstoragelocation kotsadm-velero-backend \
        || kubernetes_has_resource "$VELERO_NAMESPACE" secret aws-credentials; then
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
