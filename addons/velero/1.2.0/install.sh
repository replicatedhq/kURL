
function velero_pre_init() {
    if [ -z "$VELERO_NAMESPACE" ]; then
        VELERO_NAMESPACE=velero
    fi
}

function velero() {
    local src="$DIR/addons/velero/1.2.0"
    local dst="$DIR/kustomize/velero"

    cp -r "$src/crd" "$dst/"
    kubectl apply -k "$dst/crd"

    cp "$src/deployment.yaml" \
        "$src/rbac.yaml" \
        "$src/restic-daemonset.yaml" \
        "$src/service.yaml" \
        "$dst/"

    render_yaml_file "$src/tmpl-kustomization.yaml" > "$dst/kustomization.yaml"
    render_yaml_file "$src/tmpl-namespace.yaml" > "$dst/namespace.yaml"

    kubectl apply -k "$dst"

    velero_binary
}

function velero_binary() {
    local id=$(docker create velero/velero:v1.2.0)
    docker cp ${id}:/velero velero
    chmod a+x velero
    mv velero /usr/local/bin/velero
}
