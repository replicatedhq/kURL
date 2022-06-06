
function local-path-storage_join() {
  local-path-storage_host_init
}

function local-path-storage() {
    local src="$DIR/addons/local-path-storage/__releasever__"
    local dst="$DIR/kustomize/local-path-storage"

    local-path-storage_host_init

    cp "$src/local-path-storage.yaml" "$dst/"

    cp "$src/tmpl-kustomization.yaml" "$dst/"

    if local_path_storage_has_default_storageclass && ! local_path_storage_is_default_storageclass ; then
        printf "${YELLOW}Existing default storage class that is not Local Path Storage detected${NC}\n"
        printf "${YELLOW}Local Path Storage will still be installed as the non-default storage class.${NC}\n"
    else
        printf "Local Path Storage will be installed as the default storage class.\n"
        cp "$src/storageclass-default-annotation.yaml" "$dst/storageclass-default-annotation.yaml"
        insert_patches_strategic_merge "$dst/kustomization.yaml" "storageclass-default-annotation.yaml"
    fi

    kubectl apply -k "$dst/"
}

function local_path_storage_is_default_storageclass() {
    if kubectl get sc local-path &> /dev/null && \
    [ "$(kubectl get sc local-path -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}')" = "true" ]; then
        return 0
    fi
    return 1
}

function local_path_storage_has_default_storageclass() {
    local hasDefaultStorageClass
    hasDefaultStorageClass=$(kubectl get sc -o jsonpath='{.items[*].metadata.annotations.storageclass\.kubernetes\.io/is-default-class}')

    if [ "$hasDefaultStorageClass" = "true" ] ; then
        return 0
    fi
    return 1
}

function local-path-storage_host_init() {
  mkdir -p /opt/local-path-storage
  chmod 700 /opt/local-path-storage
}
