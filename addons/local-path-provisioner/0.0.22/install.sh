
function local-path-provisioner_join() {
  local-path-provisioner_host_init
}

function local-path-provisioner() {
    local src="$DIR/addons/local-path-provisioner/0.0.22"
    local dst="$DIR/kustomize/local-path-provisioner"

    local-path-provisioner_host_init

    cp "$src/local-path-provisioner.yaml" "$dst/"

    cp "$src/kustomization.yaml" "$dst/"

    if local_path_provisioner_has_default_storageclass && ! local_path_provisioner_is_default_storageclass ; then
        printf "${YELLOW}Existing default storage class that is not Local Path Storage detected${NC}\n"
        printf "${YELLOW}Local Path Storage will still be installed as the non-default storage class.${NC}\n"
    else
        printf "Local Path Storage will be installed as the default storage class.\n"
        cp "$src/storageclass-default-annotation.yaml" "$dst/storageclass-default-annotation.yaml"
        insert_patches_strategic_merge "$dst/kustomization.yaml" "storageclass-default-annotation.yaml"
    fi

    kubectl apply -k "$dst/"
}

function local_path_provisioner_is_default_storageclass() {
    if kubectl get sc local-path &> /dev/null && \
    [ "$(kubectl get sc local-path -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}')" = "true" ]; then
        return 0
    fi
    return 1
}

function local_path_provisioner_has_default_storageclass() {
    local hasDefaultStorageClass
    hasDefaultStorageClass=$(kubectl get sc -o jsonpath='{.items[*].metadata.annotations.storageclass\.kubernetes\.io/is-default-class}')

    if [ "$hasDefaultStorageClass" = "true" ] ; then
        return 0
    fi
    return 1
}

function local-path-provisioner_host_init() {
  mkdir -p /opt/local-path-provisioner
  chmod 700 /opt/local-path-provisioner
}

