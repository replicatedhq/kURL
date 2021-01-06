
function contour_pre_init() {
    if [ -z "$CONTOUR_NAMESPACE" ]; then
        CONTOUR_NAMESPACE=projectcontour
    fi
}

function contour() {
    local src="$DIR/addons/contour/1.7.0"
    local dst="$DIR/kustomize/contour"

    cp "$src/contour.yaml" "$dst/"
    cp "$src/patches/service-patch.yaml" "$dst/"
    cp "$src/patches/job-image.yaml" "$dst/"

    if [ -z "$CONTOUR_TLS_MINIMUM_PROTOCOL_VERSION" ]; then
        CONTOUR_TLS_MINIMUM_PROTOCOL_VERSION="1.2"
    fi

    render_yaml_file "$src/tmpl-configmap.yaml" > "$dst/configmap.yaml"
    render_yaml_file "$src/tmpl-kustomization.yaml" > "$dst/kustomization.yaml"
    render_yaml_file "$src/tmpl-namespace.yaml" > "$dst/namespace.yaml"

    # NodePort services in old namespace conflict
    if kubectl get namespace heptio-contour &>/dev/null && [ "$CONTOUR_NAMESPACE" != heptio-contour ]; then
        kubectl delete namespace heptio-contour
    fi

    kubectl create namespace "$CONTOUR_NAMESPACE" 2>/dev/null || true

    kubectl apply -k "$dst/"
}
