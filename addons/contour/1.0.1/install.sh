
function contour_pre_init() {
    if [ -z "$CONTOUR_NAMESPACE" ]; then
        CONTOUR_NAMESPACE=projectcontour
    fi
}

function contour() {
    local src="$DIR/addons/contour/1.0.1"
    local dst="$DIR/kustomize/contour"

    cp "$src/common.yaml" "$dst/"
    cp "$src/deployment.yaml" "$dst/"
    cp "$src/rbac.yaml" "$dst/"
    cp "$src/service.yaml" "$dst/"

    cp "$src/patches/service-patch.yaml" "$dst/"

    render_yaml_file "$src/tmpl-kustomization.yaml" > "$dst/kustomization.yaml"
    render_yaml_file "$src/tmpl-namespace.yaml" > "$dst/namespace.yaml"

    # NodePort services in old namespace conflict
    if kubectl get namespace heptio-contour &>/dev/null && [ "$CONTOUR_NAMESPACE" != heptio-contour ]; then
        kubectl delete namespace heptio-contour
    fi

    kubectl create namespace "$CONTOUR_NAMESPACE" 2>/dev/null || true

    kubectl apply -k "$dst/"
}
