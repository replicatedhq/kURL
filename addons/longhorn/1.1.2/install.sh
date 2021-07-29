DID_MIGRATE_ROOK_PVCS=

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

    maybe_migrate_from_rook
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

    if [ "$desired" = "$ready" ] && [ -n "$desired" ] && [ "$desired" != "0" ]; then
        return 0
    fi
    return 1
}

function longhorn_join() {
    longhorn_host_init
}

function longhorn_host_init() {
    longhorn_install_iscsi_if_missing
    longhorn_install_nfs_utils_if_missing
    mkdir -p /var/lib/longhorn
    chmod 700 /var/lib/longhorn
}

function longhorn_install_iscsi_if_missing() {
    local src="$DIR/addons/longhorn/$LONGHORN_VERSION"

    if ! systemctl list-units | grep -q iscsid ; then
        case "$LSB_DIST" in
            ubuntu)
                dpkg_install_host_archives "$src" open-iscsi
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

    if ! systemctl list-units | grep -q nfs-utils ; then
        case "$LSB_DIST" in
            ubuntu)
                dpkg_install_host_archives "$src" nfs-common
                ;;

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

function longhorn_preflight() {
    local src="${DIR}/addons/longhorn/${LONGHORN_VERSION}"
    echo "${src}/host-preflight.yaml"
}

function check_mount_propagation() {
    local src=$1

    kubectl get ns longhorn-system >/dev/null 2>&1 || kubectl create ns longhorn-system >/dev/null 2>&1
    kubectl delete -n longhorn-system ds longhorn-environment-check 2>/dev/null || true

    render_yaml_file "$src/tmpl-mount-propagation.yaml" > "$src/mount-propagation.yaml"
    kubectl apply -f "$src/mount-propagation.yaml"
    echo "Waiting for the Longhorn Mount Propagation Check Daemonset to be ready"
    spinner_until 120 longhorn_daemonset_is_ready longhorn-environment-check

    validate_longhorn_ds

    kubectl delete -f "$src/mount-propagation.yaml"
}

# pass if at least one node will support longhorn, but with a warning if there are nodes that won't
# only fail if there is no chance that longhorn will work on any nodes, as installations may have dedicated 'storage' vs 'not-storage' nodes
function validate_longhorn_ds() {
    local allpods=$(kubectl get daemonsets -n longhorn-system longhorn-environment-check --no-headers | tr -s ' ' | cut -d ' ' -f4)
    local bidirectional=$(kubectl get pods -n longhorn-system -l app=longhorn-environment-check -o=jsonpath='{.items[*].spec.containers[0].volumeMounts[*]}' | grep -o 'Bidirectional' | wc -l)

    if [ "$allpods" == "" ] || [ "$allpods" -eq "0" ]; then
        logWarn "unable to determine health and status of longhorn-environment-check daemonset"
    else
        if [ "$bidirectional" -lt "$allpods" ]; then
            logWarn "Only $bidirectional of $allpods nodes support Longhorn storage"
        else
            echo "All nodes support bidirectional mount propagation"
        fi

        if [ "$bidirectional" -eq "0" ]; then
            bail "No nodes with mount propagation enabled detected - Longhorn will not work. See https://longhorn.io/docs/1.1.1/deploy/install/#installation-requirements for details"
        fi
    fi
}

# if rook-ceph is installed but is not specified in the kURL spec, migrate data from rook-ceph to longhorn
function maybe_migrate_from_rook() {
    if [ -z "$ROOK_VERSION" ]; then
        if kubectl get ns | grep -q rook-ceph; then
            rook_ceph_to_longhorn
            export DID_MIGRATE_ROOK_PVCS="1" # used to automatically delete rook-ceph if object store data was also migrated
        fi
    fi
}
