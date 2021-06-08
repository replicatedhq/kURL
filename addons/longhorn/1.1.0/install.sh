function longhorn_pre_init() {
    if [ -z "$LONGHORN_UI_BIND_PORT" ]; then
        LONGHORN_UI_BIND_PORT="30880"
    fi
    if [ -z "$LONGHORN_UI_REPLICA_COUNT" ]; then
        LONGHORN_UI_REPLICA_COUNT="0"
    fi
}

function longhorn() {
    local src="$DIR/addons/longhorn/$LONGHORN_VERSION"
    local dst="$DIR/kustomize/longhorn"

    if longhorn_has_default_storageclass && ! longhorn_is_default_storageclass ; then
        printf "${YELLOW}Existing default storage class that is not Longhorn detected${NC}\n"
        printf "${YELLOW}Longhorn will still be installed as the non-default storage class.${NC}\n"
        cp "$src/storageclass-configmap.yaml" "$dst/"    
    else
        printf "Longhorn will be installed as the default storage class.\n"
        cp "$src/storageclass-default-configmap.yaml" "$dst/storageclass-configmap.yaml"
    fi

    longhorn_host_init

    cp "$src/kustomization.yaml" "$dst/"
    cp "$src/crds.yaml" "$dst/"
    cp "$src/driver.yaml" "$dst/"
    cp "$src/manager.yaml" "$dst/"
    cp "$src/namespace.yaml" "$dst/"
    cp "$src/psp.yaml" "$dst/"
    cp "$src/rbac.yaml" "$dst/"
    cp "$src/settings-configmap.yaml" "$dst/"      # TODO (dan): Minio Addon integration
    if [ "$KUBERNETES_TARGET_VERSION_MINOR" -lt "17" ]; then
        sed -i "s/system-node-critical/longhorn-critical/g" "$dst/settings-configmap.yaml"
        cp "$src/priority-class.yaml" "$dst/"
        insert_resources "$dst/kustomization.yaml" priority-class.yaml
    fi
    

    render_yaml_file "$src/tmpl-ui-service.yaml" > "$dst/ui-service.yaml"
    render_yaml_file "$src/tmpl-ui-deployment.yaml" > "$dst/ui-deployment.yaml"

    kubectl apply -k "$dst/"

    echo "Waiting for Longhorn Manager to create Storage Class"
    spinner_until 120 kubernetes_resource_exists longhorn-system sc longhorn

    echo "Waiting for Longhorn Manager Daemonset to be ready"
    spinner_until 180 longhorn_manager_daemonset_is_ready
}

function longhorn_is_default_storageclass() {
    if kubectl get sc longhorn &> /dev/null && \
    [ "$(kubectl get sc longhorn -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}')" = "true" ]; then
        return 0
    fi
    return 1    
}

function longhorn_has_default_storageclass() {
    local hasDefaultStorageClass
    hasDefaultStorageClass=$(kubectl get sc -o jsonpath='{.items[*].metadata.annotations.storageclass\.kubernetes\.io/is-default-class}')
        
    if [ "$hasDefaultStorageClass" = "true" ] ; then
        return 0
    fi
    return 1
}

function longhorn_manager_daemonset_is_ready() {
    local desired=$(kubectl get daemonsets -n longhorn-system longhorn-manager --no-headers | tr -s ' ' | cut -d ' ' -f2)
    local ready=$(kubectl get daemonsets -n longhorn-system longhorn-manager --no-headers | tr -s ' ' | cut -d ' ' -f4)
        
    if [ "$desired" = "$ready" ] ; then
        return 0
    fi
    return 1
}

function longhorn_join() {
    longhorn_host_init
}

function longhorn_host_init() {
    LONGHORN_HOST_PACKAGES_INSTALL=0
    longhorn_install_iscsi_if_missing
    longhorn_install_nfs_utils_if_missing 
}

function longhorn_install_iscsi_if_missing() {
    local src="$DIR/addons/longhorn/$LONGHORN_VERSION"

    if ! systemctl list-units | grep -q iscsid; then
        LONGHORN_HOST_PACKAGES_INSTALL=1
        case "$LSB_DIST" in
            ubuntu)
                dpkg_install_host_packages "$src" open-iscsi
                ;;

            centos|rhel|amzn|ol)
                yum_install_host_archives "$src" iscsi-initiator-utils
                ;;
        esac
    fi

    if ! systemctl -q is-active iscsid; then
        systemctl start iscsid
    fi

    if ! systemctl -q is-enabled iscsid; then
        systemctl enable iscsid
    fi
}

function longhorn_install_nfs_utils_if_missing() {
    local src="$DIR/addons/longhorn/$LONGHORN_VERSION"

    if ! systemctl list-units | grep -q nfs-utils; then
        LONGHORN_HOST_PACKAGES_INSTALL=1
        case "$LSB_DIST" in
            centos|rhel|amzn|ol)
                yum_install_host_archives "$src" nfs-utils
                ;;
        esac
    fi

    if ! systemctl -q is-active nfs-utils; then
        systemctl start nfs-utils
    fi

    if ! systemctl -q is-enabled nfs-utils; then
        systemctl enable nfs-utils
    fi
}
