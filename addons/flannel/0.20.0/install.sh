#!/bin/bash

export POD_CIDR
export POD_CIDR_RANGE
export POD_CIDR_IPV6
export EXISTING_POD_CIDR

export FLANNEL_ENABLE_IPV4=${FLANNEL_ENABLE_IPV4:-true}
export FLANNEL_ENABLE_IPV6=${FLANNEL_ENABLE_IPV6:-false} # TODO: support ipv6
export FLANNEL_BACKEND=${FLANNEL_BACKEND:-vxlan} # TODO: support encryption

function flannel_pre_init() {
    local src="$DIR/addons/flannel/$FLANNEL_VERSION"
    local dst="$DIR/kustomize/flannel"

    if flannel_weave_conflict ; then
        bail "Migrations from Weave to Flannel are not supported"
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

    kubectl -n kube-flannel apply -k "$dst/"
    
    # We will remove the flannel pods to let it be re-created
    # in order to workaround the issue scenario described in
    # https://github.com/flannel-io/flannel/issues/1721
    if [ "$KUBERNETES_UPGRADE" == "1" ]; then
       log "Restarting kube-flannel pods"
       kubectl rollout restart --namespace=kube-flannel daemonset/kube-flannel-ds
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

function flannel_already_applied() {
    # We will remove the flannel pods to let it be re-created
    # in order to workaround the issue scenario described in
    # https://github.com/flannel-io/flannel/issues/1721
    if [ "$KUBERNETES_UPGRADE" == "1" ]; then
       log "Restarting kube-flannel pods"
       kubectl rollout restart --namespace=kube-flannel daemonset/kube-flannel-ds
    fi

    flannel_ready_spinner
    check_network
}
