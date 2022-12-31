#!/bin/bash

export POD_CIDR
export POD_CIDR_RANGE
export POD_CIDR_IPV6
export EXISTING_POD_CIDR

export FLANNEL_ENABLE_IPV4=true
export FLANNEL_ENABLE_IPV6=false # TODO: support ipv6
export FLANNEL_BACKEND=vxlan # TODO: support encryption

function flannel_pre_init() {
    local src="$DIR/addons/flannel/$FLANNEL_VERSION"
    local dst="$DIR/kustomize/flannel"

    if flannel_weave_conflict ; then
        if ! flannel_is_single_node; then
            bail "Migrations from Weave to Flannel are not supported"
        fi
    fi
    if flannel_antrea_conflict ; then
        bail "Migrations from Antrea to Flannel are not supported"
    fi

    flannel_init_pod_subnet
}

function flannel() {
    local src="$DIR/addons/flannel/$FLANNEL_VERSION"
    local dst="$DIR/kustomize/flannel"

    cp "$src"/yaml/* "$dst/"

    flannel_render_config

    if flannel_weave_conflict; then
        weave_to_flannel
    else
        kubectl -n kube-flannel apply -k "$dst/"
    fi

    flannel_ready_spinner
    check_network
}

function flannel_init_pod_subnet() {
    POD_CIDR="$FLANNEL_POD_CIDR"
    POD_CIDR_RANGE="$FLANNEL_POD_CIDR_RANGE"

    cp "$src/kubeadm.yaml" "$DIR/kustomize/kubeadm/init-patches/flannel.yaml"

    if commandExists kubectl; then
        EXISTING_POD_CIDR=$(kubectl -n kube-system get cm kubeadm-config -oyaml 2>/dev/null | grep podSubnet | awk '{ print $NF }')
    fi
}

function flannel_render_config() {
    render_yaml_file_2 "$src/template/kube-flannel-cfg.patch.tmpl.yaml" > "$dst/kube-flannel-cfg.patch.yaml"

    if [ "$FLANNEL_ENABLE_IPV6" = "true" ] && [ -n "$POD_CIDR_IPV6" ]; then
        render_yaml_file_2 "$src/template/ipv6.patch.tmpl.yaml" > "$dst/ipv6.patch.yaml"
        insert_patches_strategic_merge "$dst/kustomization.yaml" ipv6.patch.yaml
    fi
}

function flannel_health_check() {
    local health=
    health="$(kubectl -n kube-flannel get pods -l app=flannel -o jsonpath="{range .items[*]}{range .status.conditions[*]}{ .type }={ .status }{'\n'}{end}{end}" 2>/dev/null)"
    if echo "$health" | grep -q '^Ready=False' ; then
        return 1
    fi
    return 0
}

function flannel_ready_spinner() {
    if ! spinner_until 180 flannel_health_check; then
        kubectl logs -n kube-flannel -l app=flannel --all-containers --tail 10
        bail "The Flannel add-on failed to deploy successfully."
    fi
}

function flannel_weave_conflict() {
    ls /etc/cni/net.d/*weave* >/dev/null 2>&1
}

function flannel_antrea_conflict() {
    ls /etc/cni/net.d/*antrea* >/dev/null 2>&1
}

function flannel_is_single_node() {
    local nodecount=
    nodecount=$(kubectl get nodes --no-headers | wc -l)
    if [ "$nodecount" -eq 1 ]; then
        return 0
    else
        return 1
    fi
}

function weave_to_flannel() {
    local dst="$DIR/kustomize/flannel"

    echo "REMOVING WEAVE"
    remove_weave

    echo "UPDATING KUBEADM FOR FLANNEL"
    flannel_kubeadm

    echo "APPLYING FLANNEL"
    kubectl -n kube-flannel apply -k "$dst/"

    sleep 60
    echo "RESTARTING KUBELET"
    sudo systemctl stop kubelet
    sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -F && sudo iptables -X
    sudo systemctl restart containerd
    sudo systemctl start kubelet

    sleep 60
    echo "RESTARTING kube-system"
    kubectl -n kube-system delete pods --all
    kubectl -n kube-flannel delete pods --all

    sleep 60
    echo "RESTARTING CSI"
    kubectl -n longhorn-system delete pods --all || true
    kubectl -n rook-ceph delete pods --all || true
    kubectl -n openebs delete pods --all || true

    sleep 60
    echo "RESTARTING ALL OTHER PODS"
    for ns in $(kubectl get ns -o name | grep -Ev '(kube-system|longhorn-system|rook-ceph|openebs|kube-flannel)' | cut -f2 -d'/'); do kubectl delete pods -n "$ns" --all; done
    sleep 60
}

function remove_weave() {
    # firstnode only
    kubectl -n kube-system delete daemonset weave-net
    kubectl -n kube-system delete rolebinding weave-net
    kubectl -n kube-system delete role weave-net
    kubectl delete clusterrolebinding weave-net
    kubectl delete clusterrole weave-net
    kubectl -n kube-system delete serviceaccount weave-net
    kubectl -n kube-system delete secret weave-passwd

    # all nodes
    sudo rm -f /opt/cni/bin/weave-*
    sudo rm -rf /etc/cni/net.d
    sudo ip link delete weave

}

function flannel_kubeadm() {
    # search for 'serviceSubnet', add podSubnet above it
    local pod_cidr_range_line=
    pod_cidr_range_line="  podSubnet: ${POD_CIDR}"
    if grep 'podSubnet:' /opt/replicated/kubeadm.conf; then
        sed -i "s_  podSubnet:.*_${pod_cidr_range_line}_" /opt/replicated/kubeadm.conf
    else
        sed -i "/serviceSubnet/ s/.*/${pod_cidr_range_line}\n&/" /opt/replicated/kubeadm.conf
    fi

    sudo kubeadm init phase upload-config kubeadm --config=/opt/replicated/kubeadm.conf
    sudo kubeadm init phase control-plane controller-manager --config=/opt/replicated/kubeadm.conf
}
