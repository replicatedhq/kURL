
function aws() {
    cp "$DIR/addons/aws/0.0.1/kustomization.yaml" "$DIR/kustomize/aws/kustomization.yaml"
    cp "$DIR/addons/aws/0.0.1/storageclass.yaml" "$DIR/kustomize/aws/storageclass.yaml"

    kubectl apply -k "$DIR/kustomize/aws/"
}

function aws_pre_init() {
    set_node_name
    cp "$DIR/addons/aws/0.0.1/kubeadm-cluster-config-v1beta2.yml" "$DIR/kustomize/kubeadm/init-patches/aws-kubeadm-cluster-config-v1beta2.yml"
    cp "$DIR/addons/aws/0.0.1/kubeadm-init-config-v1beta2.yml" "$DIR/kustomize/kubeadm/init-patches/aws-kubeadm-init-config-v1beta2.yml"
}

function aws_join() {
    set_node_name
    cp "$DIR/addons/aws/0.0.1/kubeadm-join-config-v1beta2.yaml" "$DIR/kustomize/kubeadm/join-patches/aws-kubeadm-join-config-v1beta2.yaml"
}

function set_node_name() {
    NODE_NAME="$(hostname -f)"
}
