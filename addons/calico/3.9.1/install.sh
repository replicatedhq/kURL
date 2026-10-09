
function calico() {
    cp "$DIR/addons/calico/3.9.1/kustomization.yaml" "$DIR/kustomize/calico/kustomization.yaml"
    cp "$DIR/addons/calico/3.9.1/calico.yaml" "$DIR/kustomize/calico/calico.yaml"

    render_yaml_file "$DIR/addons/calico/3.9.1/tmpl-daemonset-pod-cidr.yaml" > "$DIR/kustomize/calico/daemonset-pod-cidr.yaml"

    kubectl apply -k "$DIR/kustomize/calico/"
}

function calico_pre_init() {
    # kubeadm.k8s.io/v1beta4 (Kubernetes 1.37+) moved controllerManager.extraArgs from a map to a
    # list of {name, value} pairs, so it needs its own patch shape.
    if [ "$(kubeadm_conf_api_version)" = "v1beta4" ]; then
        cp "$DIR/addons/calico/3.9.1/kubeadm-cluster-config-v1beta4.yml" "$DIR/kustomize/kubeadm/init-patches/calico-kubeadm-cluster-config-v1beta2.yml"
    else
        cp "$DIR/addons/calico/3.9.1/kubeadm-cluster-config-v1beta2.yml" "$DIR/kustomize/kubeadm/init-patches/calico-kubeadm-cluster-config-v1beta2.yml"
    fi
    cp "$DIR/addons/calico/3.9.1/kubeproxy-config-v1alpha1.yml" "$DIR/kustomize/kubeadm/init-patches/calico-kubeproxy-config-v1alpha1.yml"

    calico_existing_pod_cidr
}

function calico_existing_pod_cidr() {
    if [ ! -e /opt/replicated/kubeadm.conf ]; then
        return 0
    fi
    EXISTING_POD_CIDR=$(cat /opt/replicated/kubeadm.conf | grep cluster-cidr | awk '{print $2}')
}
