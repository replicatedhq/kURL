
function calico() {
    cp "$DIR/addons/calico/3.9.1/kustomization.yaml" "$DIR/kustomize/calico/kustomization.yaml"
    cp "$DIR/addons/calico/3.9.1/calico.yaml" "$DIR/kustomize/calico/calico.yaml"

    render_yaml_file "$DIR/addons/calico/3.9.1/tmpl-daemonset-pod-cidr.yaml" > "$DIR/kustomize/calico/daemonset-pod-cidr.yaml"

    kubectl apply -k "$DIR/kustomize/calico/"

	#calico_ip_pool
}

function calico_pre_init() {
    cp "$DIR/addons/calico/3.9.1/kubeadm-cluster-config-v1beta2.yml" "$DIR/kustomize/kubeadm/init-patches/calico-kubeadm-cluster-config-v1beta2.yml"
    cp "$DIR/addons/calico/3.9.1/kubeproxy-config-v1alpha1.yml" "$DIR/kustomize/kubeadm/init-patches/calico-kubeproxy-config-v1alpha1.yml"
}

function calico_ip_pool() {
    curl -O -L  https://github.com/projectcalico/calicoctl/releases/download/v3.9.1/calicoctl
    chmod +x calicoctl

    if DATASTORE_TYPE=kubernetes KUBECONFIG=/etc/kubernetes/admin.conf ./calicoctl get ipPool | grep -q kurl.ippool-1; then
        return 0
    fi

    cat > ippool.yaml  <<EOF
apiVersion: projectcalico.org/v3
kind: IPPool
metadata:
  name: kurl.ippool-1
spec:
  cidr: 10.32.0.0/12
  ipipMode: CrossSubnet
  natOutgoing: true
  disabled: false
  nodeSelector: all()
EOF
    DATASTORE_TYPE=kubernetes KUBECONFIG=/etc/kubernetes/admin.conf ./calicoctl create -f ippool.yaml
}
