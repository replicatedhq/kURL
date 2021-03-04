
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
    local src="$DIR/addons/contour/1.13.1"
    local dst="$DIR/kustomize/contour"

    cp "$src/contour.yaml" "$dst/"

    render_yaml_file "$src/tmpl-configmap.yaml" > "$dst/configmap.yaml"
    render_yaml_file "$src/tmpl-kustomization.yaml" > "$dst/kustomization.yaml"
    render_yaml_file "$src/tmpl-namespace.yaml" > "$dst/namespace.yaml"
    render_yaml_file "$src/tmpl-service-patch.yaml" > "$dst/service-patch.yaml"

    # NodePort services in old namespace conflict
    if kubectl get namespace heptio-contour &>/dev/null && [ "$CONTOUR_NAMESPACE" != heptio-contour ]; then
        kubectl delete namespace heptio-contour
    fi

    # Revised the job image; if it exists, don't attempt to re-run
    if ! kubectl get -n "$CONTOUR_NAMESPACE" job/contour-certgen-v1.13.1 &>/dev/null ; then
        cp "$src/batch.yaml" "$dst/"
        sed -i '/- configmap.yaml/ a - batch.yaml' "$dst/kustomization.yaml"
    fi

    kubectl create namespace "$CONTOUR_NAMESPACE" 2>/dev/null || true

    kubectl apply -k "$dst/"
}
