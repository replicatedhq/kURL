
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

    OBJECT_STORE_ACCESS_KEY=$(kubectl -n rook-ceph get secret rook-ceph-object-user-rook-ceph-store-kurl -o yaml | grep AccessKey | awk '{print $2}' | base64 --decode)
    OBJECT_STORE_SECRET_KEY=$(kubectl -n rook-ceph get secret rook-ceph-object-user-rook-ceph-store-kurl -o yaml | grep SecretKey | awk '{print $2}' | base64 --decode)
    OBJECT_STORE_CLUSTER_IP=$(kubectl -n rook-ceph get service rook-ceph-rgw-rook-ceph-store | tail -n1 | awk '{ print $3}')

    if [ -z "$OBJECT_STORE_ACCESS_KEY" ] || [ -z "$OBJECT_STORE_SECRET_KEY" ] || [ -z "$OBJECT_STORE_CLUSTER_IP" ]; then
        echo "Local RGW store not configured. Skipping creation of new local RWG backend for Velero"
        return 0
    fi

    # create the velero bucket
    local acl="x-amz-acl:private"
    local d=$(date +"%a, %d %b %Y %T %z")
    local string="PUT\n\n\n${d}\n${acl}\n/$VELERO_LOCAL_BUCKET"
    local sig=$(echo -en "${string}" | openssl sha1 -hmac "${OBJECT_STORE_SECRET_KEY}" -binary | base64)
    curl -X PUT  \
        -H "Host: $OBJECT_STORE_CLUSTER_IP" \
        -H "Date: $d" \
        -H "$acl" \
        -H "Authorization: AWS $OBJECT_STORE_ACCESS_KEY:$sig" \
        "http://$OBJECT_STORE_CLUSTER_IP/$VELERO_LOCAL_BUCKET" >/dev/null
    echo "Created bucket $VELERO_LOCAL_BUCKET"

    render_yaml_file "$src/tmpl-backupstoragelocation.yaml" > "$dst/backupstoragelocation.yaml"
    insert_resources "$dst/kustomization.yaml" backupstoragelocation.yaml
}
