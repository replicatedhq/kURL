
function weave() {
    cp "$DIR/addons/weave/2.5.2/kustomization.yaml" "$DIR/kustomize/weave/kustomization.yaml"
    cp "$DIR/addons/weave/2.5.2/rbac.yaml" "$DIR/kustomize/weave/rbac.yaml"
    cp "$DIR/addons/weave/2.5.2/daemonset.yaml" "$DIR/kustomize/weave/daemonset.yaml"

    if [ "$ENCRYPT_NETWORK" != "0" ]; then
        # don't change existing secrets because pods that start after will have a different value
        if ! kubernetes_resource_exists kube-system secret weave-passwd; then
            weave_resource_secret
        fi
        weave_patch_encrypt
        weave_warn_if_sleeve
    fi

    if [ -n "$IP_ALLOC_RANGE" ]; then
        weave_patch_ip_alloc_range
    fi

    kubectl apply -k "$DIR/kustomize/weave/"
}

function weave_resource_secret() {
    insert_resources "$DIR/kustomize/weave/kustomization.yaml" secret.yaml

    WEAVE_PASSWORD=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c9)
    render_yaml_file "$DIR/addons/weave/2.5.2/tmpl-secret.yaml" > "$DIR/kustomize/weave/secret.yaml"
}

function weave_patch_encrypt() {
    insert_patches_strategic_merge "$DIR/kustomize/weave/kustomization.yaml" encrypt.yaml
    cp "$DIR/addons/weave/2.5.2/encrypt.yaml" "$DIR/kustomize/weave/encrypt.yaml"
}

function weave_patch_ip_alloc_range() {
    insert_patches_strategic_merge "$DIR/kustomize/weave/kustomization.yaml" ip-alloc-range.yaml
    render_yaml_file "$DIR/addons/weave/2.5.2/tmpl-ip-alloc-range.yaml" > "$DIR/kustomize/weave/ip-alloc-range.yaml"
}

function weave_warn_if_sleeve() {
    local kernel_major=$(uname -r | cut -d'.' -f1)
    local kernel_minor=$(uname -r | cut -d'.' -f2)
    if [ "$kernel_major" -lt "4" ] || ([ "$kernel_major" -lt "5" ] && [ "$kernel_minor" -lt "3" ]); then
        printf "${YELLOW}This host will not be able to establish optimized network connections with other peers in the Kubernetes cluster.\nRefer to the Replicated networking guide for help.\n\nhttp://help.replicated.com/docs/kubernetes/customer-installations/networking/${NC}\n"
    fi
}
