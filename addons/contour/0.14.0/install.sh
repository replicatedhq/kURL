
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
