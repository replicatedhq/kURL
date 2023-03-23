DID_MIGRATE_ROOK_OBJECT_STORE=

function minio_pre_init() {
    if [ -z "$MINIO_NAMESPACE" ]; then
        MINIO_NAMESPACE=minio
    fi

    if [ -z "$MINIO_CLAIM_SIZE" ]; then
        MINIO_CLAIM_SIZE="10Gi"
    fi
}

function minio() {
    local src="$DIR/addons/minio/2022-10-05T14-58-27Z"
    local dst="$DIR/kustomize/minio"

    render_yaml_file "$src/tmpl-kustomization.yaml" > "$dst/kustomization.yaml"
    render_yaml_file "$src/tmpl-namespace.yaml" > "$dst/namespace.yaml"

    cp "$src/deployment.yaml" "$dst/"
    cp "$src/service.yaml" "$dst/"

    if [ -n "$MINIO_HOSTPATH" ]; then
        render_yaml_file "$src/tmpl-deployment-hostpath.yaml" > "$dst/deployment-hostpath.yaml"
        insert_patches_strategic_merge "$dst/kustomization.yaml" deployment-hostpath.yaml
    else
        render_yaml_file "$src/tmpl-pvc.yaml" > "$dst/pvc.yaml"
        insert_resources "$dst/kustomization.yaml" pvc.yaml
        render_yaml_file "$src/tmpl-deployment-pvc.yaml" > "$dst/deployment-pvc.yaml"
        insert_patches_strategic_merge "$dst/kustomization.yaml" deployment-pvc.yaml
    fi

    minio_creds "$src" "$dst"

    kubectl apply -k "$dst/"

    allow_pvc_resize

    minio_object_store_output

    minio_migrate_from_rgw

    minio_wait_for_health
}

function minio_already_applied() {
    minio_object_store_output

    minio_migrate_from_rgw
}

function minio_creds() {
    local src="$1"
    local dst="$2"

    local MINIO_ACCESS_KEY=kurl
    local MINIO_SECRET_KEY=$(kubernetes_secret_value minio minio-credentials MINIO_SECRET_KEY)

    if [ -z "$MINIO_SECRET_KEY" ]; then
        MINIO_SECRET_KEY=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c9)
    fi

    render_yaml_file "$src/tmpl-creds-secret.yaml" > "$dst/creds-secret.yaml"
    insert_resources "$dst/kustomization.yaml" creds-secret.yaml

    if [ -n "$MINIO_HOSTPATH" ]; then
        # in the case of using a "hostPath", minio will generate a config in a ".minio.sys" directory
        # that is used to control access to that hostPath. this can be a problem when that hostpath
        # is a directory in a shared file system (an NFS mount for example) and the installer is being
        # run on a fresh instance, because new credentials will be generated and minio won't be able access the old data,
        # so we make sure that the config is regenerated from the current minio credentials.

        # initialize some common variables
        local MINIO_CONFIG_PATH="$MINIO_HOSTPATH/.minio.sys/config"
        local KURL_DIR="$MINIO_HOSTPATH/.kurl"
        local MINIO_KEYS_SHA_FILE="$KURL_DIR/minio-keys-sha.txt"
        local NEW_MINIO_KEYS_SHA=$(echo -n "$MINIO_ACCESS_KEY,$MINIO_SECRET_KEY" | sha256sum)

        if should_reset_minio_config; then
            reset_minio_config
        fi
        if [ ! -d "$MINIO_CONFIG_PATH" ]; then
            kubernetes_scale_down ${MINIO_NAMESPACE} deployment minio
        fi
        write_minio_keys_sha_file
    fi
}

function should_reset_minio_config() {
    if [ -z "$MINIO_HOSTPATH" ]; then
        return 1
    fi

    if [ ! -d "$MINIO_CONFIG_PATH" ]; then
        return 1
    fi

    if ! kubernetes_resource_exists ${MINIO_NAMESPACE} secret minio-credentials; then
        return 0
    fi

    if [ ! -f "$MINIO_KEYS_SHA_FILE" ]; then
        return 0
    fi

    local EXISTING_MINIO_KEYS_SHA=$(cat $MINIO_KEYS_SHA_FILE)
    if [ "$NEW_MINIO_KEYS_SHA" == "$EXISTING_MINIO_KEYS_SHA" ]; then
        return 1
    fi

    return 0
}

function reset_minio_config() {
    if [ ! -d "$MINIO_CONFIG_PATH" ]; then
        return 0
    fi

    printf "\n"
    printf "\n"
    printf "${RED}The $MINIO_HOSTPATH directory was previously configured by a different minio instance.\n"
    printf "Proceeding will re-configure it to be used only by this new minio instance, and any other minio instance using this location will no longer have access.\n"
    printf "If you are attempting to fully restore a prior installation, such as a disaster recovery scenario, this action is expected. Would you like to continue?${NC} "

    if ! confirmN ; then
        bail "\n\nWill not re-configure $MINIO_HOSTPATH."
    fi

    rm -rf "$MINIO_CONFIG_PATH"
}

function write_minio_keys_sha_file() {
    if [ ! -d "$KURL_DIR" ]; then
        mkdir -p "$KURL_DIR"
    fi

    echo "$NEW_MINIO_KEYS_SHA" > "$MINIO_KEYS_SHA_FILE"
}

function minio_object_store_output() {
    # don't overwrite rook if also running
    if object_store_exists; then
        return 0;
    fi
    # create the docker-registry bucket through the S3 API
    OBJECT_STORE_ACCESS_KEY=$(kubectl -n ${MINIO_NAMESPACE} get secret minio-credentials -ojsonpath='{ .data.MINIO_ACCESS_KEY }' | base64 --decode)
    OBJECT_STORE_SECRET_KEY=$(kubectl -n ${MINIO_NAMESPACE} get secret minio-credentials -ojsonpath='{ .data.MINIO_SECRET_KEY }' | base64 --decode)
    OBJECT_STORE_CLUSTER_IP=$(kubectl -n ${MINIO_NAMESPACE} get service minio | tail -n1 | awk '{ print $3}')
    OBJECT_STORE_CLUSTER_HOST="http://minio.${MINIO_NAMESPACE}"

    minio_wait_for_health
}

function minio_wait_for_health() {
    printf "awaiting minio deployment\n"
    spinner_until 300 deployment_fully_updated minio minio

    MINIO_CLUSTER_IP=$(kubectl -n ${MINIO_NAMESPACE} get service minio | tail -n1 | awk '{ print $3}')
    printf "awaiting minio readiness\n"
    if ! spinner_until 120 minio_ready; then
        bail "Minio API failed to report healthy"
    fi
    printf "awaiting minio endpoint\n"
    if ! spinner_until 120 minio_endpoint_exists; then
        bail "Minio endpoint failed to be discovered"
    fi
}

function minio_ready() {
    curl --noproxy "*" -s "http://$MINIO_CLUSTER_IP/minio/health/ready"
}

function minio_endpoint_exists() {
    local minio_endpoint
    minio_endpoint=$(kubectl get endpoints -n minio minio | grep -v NAME | awk '{ print $2 }')
    if [ "$minio_endpoint" == "<none>" ]; then
        return 1
    fi
    return 0
}

function minio_migrate_from_rgw() {
    if [ -n "$ROOK_VERSION" ]; then # if rook is still specified in the kURL spec, don't migrate
        return
    fi

    if ! kubernetes_resource_exists rook-ceph deployment rook-ceph-rgw-rook-ceph-store-a; then # if rook is not installed, don't migrate
        return
    fi

    minio_wait_for_health

    migrate_rgw_to_minio
    add_rook_store_object_migration_status
}

function allow_pvc_resize() {
    if kubernetes_resource_exists "$MINIO_NAMESPACE" pvc minio-pv-claim; then
        # check if the minio PVC's current size is not the desired size
        current_size=$(kubectl get pvc -n "$MINIO_NAMESPACE" minio-pv-claim -o jsonpath='{.status.capacity.storage}')
        desired_size=$(kubectl get pvc -n "$MINIO_NAMESPACE" minio-pv-claim -o jsonpath='{.spec.resources.requests.storage}')

        if [ -z "$current_size" ]; then
            # if the current size is not set, then the PVC does not yet have a PV
            # this is something that will be the case on first install, and the PV will be created with the right size
            return
        fi

        if [ "$current_size" != "$desired_size" ]; then
            # if it is not at the desired size, scale down the minio deployment
            kubectl scale deployment -n "$MINIO_NAMESPACE" minio --replicas=0

            printf "Waiting up to one minute for Minio PVC size to change from %s to %s\n" "$current_size" "$desired_size"
            n=0
            while [ "$current_size" != "$desired_size" ] && [ $n -lt 30 ]; do
                sleep 2
                current_size=$(kubectl get pvc -n "$MINIO_NAMESPACE" minio-pv-claim -o jsonpath='{.status.capacity.storage}')
                n="$((n+1))"
            done

            if [ "$current_size" == "$desired_size" ]; then
                printf "Successfully updated Minio PVC size to %s\n" "$current_size"
            else
                printf "Failed to update Minio PVC size from %s to %s after 1m, continuing with installation process\n" "$current_size" "$desired_size"
            fi

            # restore the scale to 1 (whether the minute of waiting worked or not)
            kubectl scale deployment -n "$MINIO_NAMESPACE" minio --replicas=1
        fi
    fi
}
