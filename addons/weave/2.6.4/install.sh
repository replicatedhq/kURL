
function weave_pre_init() {
    weave_use_existing_network
}

function weave() {
    cp "$DIR/addons/weave/2.6.4/kustomization.yaml" "$DIR/kustomize/weave/kustomization.yaml"
    cp "$DIR/addons/weave/2.6.4/rbac.yaml" "$DIR/kustomize/weave/rbac.yaml"
    cp "$DIR/addons/weave/2.6.4/daemonset.yaml" "$DIR/kustomize/weave/daemonset.yaml"

    if [ "$ENCRYPT_NETWORK" != "0" ]; then
        # don't change existing secrets because pods that start after will have a different value
        if ! kubernetes_resource_exists kube-system secret weave-passwd; then
            weave_resource_secret
        fi
        weave_patch_encrypt
        weave_warn_if_sleeve
    fi

    if [ -n "$POD_CIDR" ]; then
        weave_patch_ip_alloc_range
    fi

    if [ -n "$NO_MASQ_LOCAL" ]; then
      weave_patch_no_masq_local
    fi

    kubectl apply -k "$DIR/kustomize/weave/"
    weave_ready_spinner
    check_network
}

function weave_resource_secret() {
    insert_resources "$DIR/kustomize/weave/kustomization.yaml" secret.yaml

    WEAVE_PASSWORD=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c9)
    render_yaml_file "$DIR/addons/weave/2.6.4/tmpl-secret.yaml" > "$DIR/kustomize/weave/secret.yaml"
}

function weave_patch_encrypt() {
    insert_patches_strategic_merge "$DIR/kustomize/weave/kustomization.yaml" encrypt.yaml
    cp "$DIR/addons/weave/2.6.4/encrypt.yaml" "$DIR/kustomize/weave/encrypt.yaml"
}

function weave_patch_ip_alloc_range() {
    insert_patches_strategic_merge "$DIR/kustomize/weave/kustomization.yaml" ip-alloc-range.yaml
    render_yaml_file "$DIR/addons/weave/2.6.4/tmpl-ip-alloc-range.yaml" > "$DIR/kustomize/weave/ip-alloc-range.yaml"
}

function weave_patch_no_masq_local() {
    local src="${DIR}/addons/weave/${WEAVE_VERSION}"
    local dst="${DIR}/kustomize/weave"

    insert_patches_strategic_merge "${dst}/kustomization.yaml" patch-no-masq-local.yaml
    render_yaml_file "${src}/tmpl-patch-no-masq-local.yaml" > "${dst}/patch-no-masq-local.yaml"
}


function weave_warn_if_sleeve() {
    local kernel_major=$(uname -r | cut -d'.' -f1)
    local kernel_minor=$(uname -r | cut -d'.' -f2)
    if [ "$kernel_major" -lt "4" ] || ([ "$kernel_major" -lt "5" ] && [ "$kernel_minor" -lt "3" ]); then
        printf "${YELLOW}This host will not be able to establish optimized network connections with other peers in the Kubernetes cluster.\nRefer to the Replicated networking guide for help.\n\nhttp://help.replicated.com/docs/kubernetes/customer-installations/networking/${NC}\n"
    fi
}

function weave_use_existing_network() {
    if weaveDev=$(ip route show dev weave 2>/dev/null); then
        EXISTING_POD_CIDR=$(echo $weaveDev | awk '{ print $1 }')
        echo "Using existing weave network: $EXISTING_POD_CIDR"
    fi
}

function weave_health_check() {
    local health="$(kubectl get pods -n kube-system -l name=weave-net -o jsonpath="{range .items[*]}{range .status.conditions[*]}{ .type }={ .status }{'\n'}{end}{end}" 2>/dev/null)"
    if [ -z "$health" ] || echo "$health" | grep -q '^Ready=False' ; then
        return 1
    fi
    return 0
}

function weave_ready_spinner() {
    if ! spinner_until 180 weave_health_check; then
      kubectl logs -n kube-system -l name=weave-net --all-containers --tail 10
      bail "The weave addon failed to deploy successfully."
    fi
}
