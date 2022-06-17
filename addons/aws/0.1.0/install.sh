
function aws() {

    local dst="$DIR/kustomize/aws"
    cp "$DIR/addons/aws/0.1.0/kustomization.yaml" "$DIR/kustomize/aws/kustomization.yaml"
    cp "$DIR/addons/aws/0.1.0/storageclass.yaml" "$DIR/kustomize/aws/storageclass.yaml"

    if [ "$AWS_EXCLUDE_STORAGE_CLASS" != "1" ]; then
        insert_resources "$dst/kustomization.yaml" storageclass.yaml
    fi

    if  [ -s "$DIR/kustomize/aws/kustomization.yaml" ]; then
        kubectl apply -k "$DIR/kustomize/aws/"
    else 
        echo "Nothing to apply"
    fi

}

function aws_pre_init() {
    verify_node_name
    cp "$DIR/addons/aws/0.1.0/kubeadm-cluster-config-v1beta2.yml" "$DIR/kustomize/kubeadm/init-patches/aws-kubeadm-cluster-config-v1beta2.yml"
    cp "$DIR/addons/aws/0.1.0/kubeadm-init-config-v1beta2.yml" "$DIR/kustomize/kubeadm/init-patches/aws-kubeadm-init-config-v1beta2.yml"
}

function aws_join() {
    verify_node_name
    cp "$DIR/addons/aws/0.1.0/kubeadm-join-config-v1beta2.yaml" "$DIR/kustomize/kubeadm/join-patches/aws-kubeadm-join-config-v1beta2.yaml"
}

function verify_node_name() {
    if [ "$(hostname -f)" != "$(hostname)" ]; then
        logFail "Its important that the name of the Node matches the private DNS entry for the instance in EC2."
        logFail "You can use hostnamectl to set the instance hostname to the FQDN that matches the EC2 private DNS entry."
        logFail "Hostname $(hostname) is different from fqdn $(hostname -f)"
        printf "Continue? "
        if ! confirmN ; then
            bail "aws addon install is aborted."
        fi
    fi
}
