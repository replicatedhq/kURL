
function calico() {
    cp "$DIR/addons/calico/3.9.1/kustomization.yaml" "$DIR/kustomize/calico/kustomization.yaml"
    cp "$DIR/addons/calico/3.9.1/calico.yaml" "$DIR/kustomize/calico/calico.yaml"

    kubectl apply -k "$DIR/kustomize/calico/"
}
