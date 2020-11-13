
function minio_pre_init() {
    if [ -z "$MINIO_NAMESPACE" ]; then
        MINIO_NAMESPACE=minio
    fi
}

function minio() {
    local src="$DIR/addons/minio/2020-01-25T02-50-51Z"
    local dst="$DIR/kustomize/minio"

    render_yaml_file "$src/tmpl-kustomization.yaml" > "$dst/kustomization.yaml"
    render_yaml_file "$src/tmpl-namespace.yaml" > "$dst/namespace.yaml"
    cp "$src/pvc.yaml" "$dst/"
    cp "$src/deployment.yaml" "$dst/"
    cp "$src/service.yaml" "$dst/"

    minio_creds "$src" "$dst"

    kubectl apply -k "$dst/"

    minio_object_store_output
}

function minio_creds() {
    local src="$1"
    local dst="$2"
 
    if kubernetes_resource_exists ${MINIO_NAMESPACE} secret minio-credentials; then
        return 0
    fi

    local MINIO_ACCESS_KEY=kurl
    local MINIO_SECRET_KEY=$(generate_password)

    render_yaml_file "$src/tmpl-creds-secret.yaml" > "$dst/creds-secret.yaml"
    insert_resources "$dst/kustomization.yaml" creds-secret.yaml
}

function minio_object_store_output() {
    # don't overwrite rook if also running
    if object_store_exists; then
        return 0;
    fi
    # create the docker-registry bucket through the S3 API
    OBJECT_STORE_ACCESS_KEY=$(kubectl -n ${MINIO_NAMESPACE} get secret minio-credentials -ojsonpath='{ .data.MINIO_ACCESS_KEY }' | base64 --decode)
    OBJECT_STORE_SECRET_KEY=$(kubectl -n ${MINIO_NAMESPACE} get secret minio-credentials -ojsonpath='{ .data.MINIO_SECRET_KEY }' | base64 --decode)
    OBJECT_STORE_CLUSTER_IP=$(kubectl -n ${MINIO_NAMESPACE} get service minio | tail -n1 | awk '{ print $3}')
    OBJECT_STORE_CLUSTER_HOST="http://minio.${MINIO_NAMESPACE}"

    if ! spinner_until 120 minio_ready; then
        bail "Minio API failed to report healthy"
    fi
}

function minio_ready() {
    curl --noproxy "*" -s "http://$OBJECT_STORE_CLUSTER_IP/minio/health/ready"
}
