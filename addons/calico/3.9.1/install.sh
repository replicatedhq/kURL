
function calico() {
    cp "$DIR/addons/calico/3.9.1/kustomization.yaml" "$DIR/kustomize/calico/kustomization.yaml"
    cp "$DIR/addons/calico/3.9.1/calico.yaml" "$DIR/kustomize/calico/calico.yaml"

    render_yaml_file "$DIR/addons/calico/3.9.1/tmpl-daemonset-pod-cidr.yaml" > "$DIR/kustomize/calico/daemonset-pod-cidr.yaml"

    kubectl apply -k "$DIR/kustomize/calico/"
}

function calico_pre_init() {
    cp "$DIR/addons/calico/3.9.1/kubeadm-cluster-config-v1beta2.yml" "$DIR/kustomize/kubeadm/init-patches/calico-kubeadm-cluster-config-v1beta2.yml"
    cp "$DIR/addons/calico/3.9.1/kubeproxy-config-v1alpha1.yml" "$DIR/kustomize/kubeadm/init-patches/calico-kubeproxy-config-v1alpha1.yml"
}
