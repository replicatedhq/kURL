
function contour_pre_init() {
    if [ -z "$CONTOUR_NAMESPACE" ]; then
        CONTOUR_NAMESPACE=projectcontour
    fi
}

function contour() {
    local src="$DIR/addons/contour/1.0.1"
    local dst="$DIR/kustomize/contour"

    cp "$src/kustomization.yaml" "$dst/"
    cp "$src/common.yaml" "$dst/"
    cp "$src/deployment.yaml" "$dst/"
    cp "$src/service.yaml" "$dst/"
    cp "$src/rbac.yaml" "$dst/"

    cp "$src/patches/service-patch.yaml" "$dst/"

    render_yaml_file "$src/tmpl-kustomization.yaml" > "$dst/kustomization.yaml"
    render_yaml_file "$src/tmpl-namespace.yaml" > "$dst/namespace.yaml"

    kubectl create namespace "$CONTOUR_NAMESPACE" 2>/dev/null || true

    kubectl apply -k "$dst/"
}
