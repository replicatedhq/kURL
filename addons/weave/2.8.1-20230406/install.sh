
function weave_pre_init() {
    weave_use_existing_network
}

function weave() {
    local src="${DIR}/addons/weave/${WEAVE_VERSION}"
    local dst="${DIR}/kustomize/weave"

    cp "${src}/kustomization.yaml" "${dst}/kustomization.yaml"
    cp "${src}/weave-daemonset-k8s-1.11.yaml" "${dst}/weave-daemonset-k8s-1.11.yaml"
    cp "${src}/patch-daemonset.yaml" "${dst}/patch-daemonset.yaml"

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

    kubectl apply -k "${dst}/"
    weave_ready_spinner
    check_network
}

function weave_resource_secret() {
    local src="${DIR}/addons/weave/${WEAVE_VERSION}"
    local dst="${DIR}/kustomize/weave"

    insert_resources "${dst}/kustomization.yaml" secret.yaml

    WEAVE_PASSWORD=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c9)
    render_yaml_file_2 "${src}/tmpl-secret.yaml" > "${dst}/secret.yaml"
}

function weave_patch_encrypt() {
    local src="${DIR}/addons/weave/${WEAVE_VERSION}"
    local dst="${DIR}/kustomize/weave"

    insert_patches_strategic_merge "${dst}/kustomization.yaml" patch-encrypt.yaml
    cp "${src}/patch-encrypt.yaml" "${dst}/patch-encrypt.yaml"
}

function weave_patch_ip_alloc_range() {
    local src="${DIR}/addons/weave/${WEAVE_VERSION}"
    local dst="${DIR}/kustomize/weave"

    insert_patches_strategic_merge "${dst}/kustomization.yaml" patch-ip-alloc-range.yaml
    render_yaml_file_2 "${src}/tmpl-patch-ip-alloc-range.yaml" > "${dst}/patch-ip-alloc-range.yaml"
}

function weave_patch_no_masq_local() {
    local src="${DIR}/addons/weave/${WEAVE_VERSION}"
    local dst="${DIR}/kustomize/weave"

    insert_patches_strategic_merge "${dst}/kustomization.yaml" patch-no-masq-local.yaml
    render_yaml_file_2 "${src}/tmpl-patch-no-masq-local.yaml" > "${dst}/patch-no-masq-local.yaml"
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
