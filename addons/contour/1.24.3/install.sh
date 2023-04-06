
function contour_pre_init() {
    if [ -z "$CONTOUR_NAMESPACE" ]; then
        CONTOUR_NAMESPACE=projectcontour
    fi

    if [ -z "$CONTOUR_TLS_MINIMUM_PROTOCOL_VERSION" ]; then
        CONTOUR_TLS_MINIMUM_PROTOCOL_VERSION="1.2"
    fi

    if [ -z "$CONTOUR_HTTP_PORT" ]; then
        CONTOUR_HTTP_PORT="80"
    fi

    if [ -z "$CONTOUR_HTTPS_PORT" ]; then
        CONTOUR_HTTPS_PORT="443"
    fi
}

function contour() {
    local src="$DIR/addons/contour/1.24.3"
    local dst="$DIR/kustomize/contour"

    cp "$src/contour.yaml" "$dst/"
    cp "$src/patches/job-image.yaml" "$dst/"
    cp "$src/patches/resource-limits.yaml" "$dst/"

    render_yaml_file "$src/tmpl-configmap.yaml" > "$dst/configmap.yaml"
    render_yaml_file "$src/tmpl-kustomization.yaml" > "$dst/kustomization.yaml"
    render_yaml_file "$src/tmpl-namespace.yaml" > "$dst/namespace.yaml"
    render_yaml_file "$src/tmpl-service-patch.yaml" > "$dst/service-patch.yaml"

    # NodePort services in old namespace conflict
    if kubectl get namespace heptio-contour &>/dev/null && [ "$CONTOUR_NAMESPACE" != heptio-contour ]; then
        kubectl delete namespace heptio-contour
    fi

    kubectl create --save-config namespace "$CONTOUR_NAMESPACE" 2>/dev/null || true

    kubectl apply -k "$dst/"
}
