ENVOY_VERSION=1.12.2

function contour() {
    local src="$DIR/addons/contour/1.0.1"
    local dst="$DIR/kustomize/contour"

    cp "$src/kustomization.yaml" "$dst/"
    cp "$src/common.yaml" "$dst/"
    cp "$src/deployment.yaml" "$dst/"
    cp "$src/service.yaml" "$dst/"
    cp "$src/rbac.yaml" "$dst/"

    cp "$src/patches/service-patch.yaml" "$dst/"

    kubectl apply -k "$dst/"
}
