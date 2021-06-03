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

    cp "$src/kustomization.yaml" "$dst/"
    cp "$src/crds.yaml" "$dst/"
    cp "$src/AllResources.yaml" "$dst/"
    cp "$src/manager-priority.yaml" "$dst/"
    cp "$src/driver-priority.yaml" "$dst/"

    if longhorn_has_default_storageclass && ! longhorn_is_default_storageclass ; then
        printf "${YELLOW}Existing default storage class that is not Longhorn detected${NC}\n"
        printf "${YELLOW}Longhorn will still be installed as the non-default storage class.${NC}\n"
    else
        printf "Longhorn will be installed as the default storage class.\n"
        cp "$src/storageclass-default-configmap.yaml" "$dst/storageclass-configmap.yaml"
        insert_patches_strategic_merge "$dst/kustomization.yaml" "storageclass-configmap.yaml"
    fi

    check_mount_propagation $src

    longhorn_host_init


    render_yaml_file "$src/tmpl-ui-service.yaml" > "$dst/ui-service.yaml"
    render_yaml_file "$src/tmpl-ui-deployment.yaml" > "$dst/ui-deployment.yaml"

    kubectl apply -f "$dst/crds.yaml"
    echo "Waiting for Longhorn CRDs to be created"
    spinner_until 120 kubernetes_resource_exists default crd engines.longhorn.io
    spinner_until 120 kubernetes_resource_exists default crd replicas.longhorn.io
    spinner_until 120 kubernetes_resource_exists default crd settings.longhorn.io
    spinner_until 120 kubernetes_resource_exists default crd volumes.longhorn.io
    spinner_until 120 kubernetes_resource_exists default crd engineimages.longhorn.io
    spinner_until 120 kubernetes_resource_exists default crd nodes.longhorn.io
    spinner_until 120 kubernetes_resource_exists default crd instancemanagers.longhorn.io
    spinner_until 120 kubernetes_resource_exists default crd sharemanagers.longhorn.io
    spinner_until 120 kubernetes_resource_exists default crd backingimages.longhorn.io
    spinner_until 120 kubernetes_resource_exists default crd backingimagemanagers.longhorn.io

    kubectl apply -k "$dst/"

    echo "Waiting for Longhorn Manager to create Storage Class"
    spinner_until 120 kubernetes_resource_exists longhorn-system sc longhorn

    echo "Waiting for Longhorn Manager Daemonset to be ready"
    spinner_until 180 longhorn_daemonset_is_ready longhorn-manager
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

function longhorn_daemonset_is_ready() {
    local dsname=$1
    local desired=$(kubectl get daemonsets -n longhorn-system $dsname --no-headers | tr -s ' ' | cut -d ' ' -f2)
    local ready=$(kubectl get daemonsets -n longhorn-system $dsname --no-headers | tr -s ' ' | cut -d ' ' -f4)

    if [ "$desired" = "$ready" ] ; then
        return 0
    fi
    return 1
}

function longhorn_join() {
    longhorn_host_init
}

function longhorn_host_init() {
    LONGHORN_HOST_PACKAGES_INSTALL="0"
    longhorn_install_service_if_missing iscsid
    longhorn_install_service_if_missing nfs-utils.service
    mkdir -p /var/lib/longhorn
    chmod 700 /var/lib/longhorn
}

function longhorn_install_service_if_missing() {
    local service=$1
    local src="$DIR/addons/longhorn/$LONGHORN_VERSION"

    if ! systemctl list-units | grep -q $service && [ "$LONGHORN_HOST_PACKAGES_INSTALL" = "0" ]; then
        LONGHORN_HOST_PACKAGES_INSTALL="1"
        install_host_archives "$src"
        printf "${YELLOW}Host packages for Longhorn installed.${NC}\n"
    fi

    if ! systemctl -q is-active $service; then
        printf "${YELLOW}$service service started${NC}\n"
        systemctl start $service
    fi

    if ! systemctl -q is-enabled $service; then
        printf "${YELLOW}$service service enabled${NC}\n"
        systemctl enable $service
    fi
}

function longhorn_preflight() {
    local src="${DIR}/addons/longhorn/${LONGHORN_VERSION}"
    echo "${src}/host-preflight.yaml"
}

function check_mount_propagation() {
    local src=$1

    kubectl get ns longhorn-system >/dev/null 2>&1 || kubectl create ns longhorn-system >/dev/null 2>&1
    kubectl delete -n longhorn-system ds longhorn-environment-check || true

    render_yaml_file "$src/tmpl-mount-propagation.yaml" > "$src/mount-propagation.yaml"
    kubectl apply -f "$src/mount-propagation.yaml"
    echo "Waiting for the Longhorn Mount Propagation Check Daemonset to be ready"
    spinner_until 120 longhorn_daemonset_is_ready longhorn-manager

    validate_longhorn_ds

    kubectl delete -f "$src/mount-propagation.yaml"
}

function validate_longhorn_ds() {
    local allSupported=true

    local allpods=$(kubectl get daemonsets -n longhorn-system longhorn-environment-check --no-headers | tr -s ' ' | cut -d ' ' -f4)
    local bidirectional=$(kubectl get pods -l app=longhorn-environment-check -o=jsonpath='{.items[*].spec.containers[0].volumeMounts[*]}' | grep -o 'Bidirectional' | wc -l)

    if [ "$allpods" == "" ]; then
        logWarn "unable to determine health and status of longhorn-environment-check daemonset"
    else
        if [ "$bidirectional" -lt "$allpods" ]; then
            logWarn "Only $bidirectional of $allpods nodes support Longhorn storage"
        fi

        if [ "$bidirectional" -eq "0" ]; then
            bail "No nodes with mount propagation enabled detected - Longhorn will not work. See https://longhorn.io/docs/1.1.1/deploy/install/#installation-requirements for details"
        fi
    fi
}
