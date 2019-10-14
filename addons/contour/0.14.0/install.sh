ENVOY_VERSION=1.10.0

function contour() {
    local src="$DIR/addons/contour/0.14.0"
    local dst="$DIR/kustomize/contour"

    cp "$src/kustomization.yaml" "$dst/"
    cp "$src/common.yaml" "$dst/"
    cp "$src/deployment.yaml" "$dst/"
    cp "$src/service.yaml" "$dst/"
    cp "$src/rbac.yaml" "$dst/"

    cp "$src/patches/deployment-images.yaml" "$dst/"
    cp "$src/patches/service-node-port.yaml" "$dst/"

    kubectl apply -k "$dst/"
}

# Let kotsadm add additional ingress
function contour_add() {
    local dst="$1"
    local NAMESPACE="$2"
    local CONTOUR_HTTP_PORT="$3"
    local CONTOUR_HTTPS_PORT="$4"
    local CONTOUR_CLASS="$5"
    local src="$DIR/addons/contour/0.14.0"

    cp "$src/kustomization.yaml" "$dst/"
    cp "$src/common.yaml" "$dst/"
    cp "$src/deployment.yaml" "$dst/"
    cp "$src/service.yaml" "$dst/"
    cp "$src/rbac.yaml" "$dst/"

    cp "$src/patches/deployment-images.yaml" "$dst/"
    cp "$src/patches/service-node-port.yaml" "$dst/"

    mkdir -p "$dst/patches"
    render_yaml_file "$src/patches/tmpl-service-node-ports.yaml" > "$dst/patches/service-node-ports.yaml"
    insert_patches_strategic_merge "$dst/kustomization.yaml" "patches/service-node-ports.yaml"

    render_yaml_file "$src/patches/tmpl-deployment-class.yaml" > "$dst/patches/deployment-class.yaml"
    insert_patches_strategic_merge "$dst/kustomization.yaml" "patches/deployment-class.yaml"

    echo "namespace: $NAMESPACE" >> "$dst/kustomization.yaml"

    kubectl apply -k "$dst/"
}
