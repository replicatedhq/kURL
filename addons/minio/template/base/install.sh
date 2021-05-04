
function minio_pre_init() {
    if [ -z "$MINIO_NAMESPACE" ]; then
        MINIO_NAMESPACE=minio
    fi
}

function minio() {
    local src="${DIR}/addons/minio/${MINIO_VERSION}"
    local dst="${DIR}/kustomize/minio"

    cp -r "${src}/crds.yaml" "${dst}/crds.yaml"
    cp -r "${src}/operator" "${dst}/operator"

    render_yaml_file "${src}/tmpl-namespace.yaml" > "${dst}/namespace.yaml"
    render_yaml_file "${src}/operator/tmpl-kustomization.yaml" > "${dst}/operator/kustomization.yaml"

    # TODO
    # if [ -n "$MINIO_HOSTPATH" ]; then
    #     render_yaml_file "$src/tmpl-deployment-hostpath.yaml" > "$dst/deployment-hostpath.yaml"
    #     insert_patches_strategic_merge "$dst/kustomization.yaml" deployment-hostpath.yaml
    # fi

    minio_creds "${src}/operator" "${dst}/operator"

    kubectl apply -f "${dst}/namespace.yaml"

    kubectl apply -f "${dst}/crds.yaml"

    spinner_until -1 minio_crds_ready

    kubectl apply -k "${dst}/operator/"

    minio_wait

    minio_object_store_output
}

function minio_creds() {
    local src="$1"
    local dst="$2"

    export MINIO_ACCESS_KEY=kurl
    export MINIO_SECRET_KEY=
    MINIO_SECRET_KEY="$(kubernetes_secret_value "${MINIO_NAMESPACE}" minio-credentials MINIO_SECRET_KEY)"

    if [ -z "${MINIO_SECRET_KEY}" ]; then
        MINIO_SECRET_KEY="$(< /dev/urandom tr -dc A-Za-z0-9 | head -c9)"
    fi

    render_yaml_file "${src}/tmpl-tenant-secret.yaml" > "${dst}/tenant-secret.yaml"
    insert_resources "$dst/kustomization.yaml" tenant-secret.yaml

    # TODO
    # if [ -n "$MINIO_HOSTPATH" ]; then
    #     # in the case of using a "hostPath", minio will generate a config in a ".minio.sys" directory
    #     # that is used to control access to that hostPath. this can be a problem when that hostpath
    #     # is a directory in a shared file system (an NFS mount for example) and the installer is being
    #     # run on a fresh instance, because new credentials will be generated and minio won't be able access the old data,
    #     # so we make sure that the config is regenerated from the current minio credentials.

    #     # initialize some common variables
    #     local MINIO_CONFIG_PATH="$MINIO_HOSTPATH/.minio.sys/config"
    #     local KURL_DIR="$MINIO_HOSTPATH/.kurl"
    #     local MINIO_KEYS_SHA_FILE="$KURL_DIR/minio-keys-sha.txt"
    #     local NEW_MINIO_KEYS_SHA=$(echo -n "$MINIO_ACCESS_KEY,$MINIO_SECRET_KEY" | sha256sum)

    #     if should_reset_minio_config; then
    #         reset_minio_config
    #     fi
    #     if [ ! -d "$MINIO_CONFIG_PATH" ]; then
    #         kubernetes_scale_down ${MINIO_NAMESPACE} deployment minio
    #     fi
    #     write_minio_keys_sha_file
    # fi
}

# function should_reset_minio_config() {
#     if [ -z "$MINIO_HOSTPATH" ]; then
#         return 1
#     fi

#     if [ ! -d "$MINIO_CONFIG_PATH" ]; then
#         return 1
#     fi

#     if ! kubernetes_resource_exists ${MINIO_NAMESPACE} secret minio-credentials; then
#         return 0
#     fi

#     if [ ! -f "$MINIO_KEYS_SHA_FILE" ]; then
#         return 0
#     fi

#     local EXISTING_MINIO_KEYS_SHA=$(cat $MINIO_KEYS_SHA_FILE)
#     if [ "$NEW_MINIO_KEYS_SHA" == "$EXISTING_MINIO_KEYS_SHA" ]; then
#         return 1
#     fi

#     return 0
# }

# function reset_minio_config() {
#     if [ ! -d "$MINIO_CONFIG_PATH" ]; then
#         return 0
#     fi

#     printf "\n"
#     printf "\n"
#     printf "${RED}The $MINIO_HOSTPATH directory was previously configured by a different minio instance.\n"
#     printf "Proceeding will re-configure it to be used only by this new minio instance, and any other minio instance using this location will no longer have access.\n"
#     printf "If you are attempting to fully restore a prior installation, such as a disaster recovery scenario, this action is expected. Would you like to continue?${NC} "

#     if ! confirmN "-t 120"; then
#         bail "\n\nWill not re-configure $MINIO_HOSTPATH."
#     fi

#     rm -rf "$MINIO_CONFIG_PATH"
# }

# function write_minio_keys_sha_file() {
#     if [ ! -d "$KURL_DIR" ]; then
#         mkdir -p "$KURL_DIR"
#     fi

#     echo "$NEW_MINIO_KEYS_SHA" > "$MINIO_KEYS_SHA_FILE"
# }

function minio_crds_ready() {
    if ! kubectl get customresourcedefinitions tenants.minio.min.io &>/dev/null; then
        return 1
    fi
    if ! kubectl get tenants --all-namespaces &>/dev/null; then
        return 1
    fi
    return 0
}

function minio_wait() {
    logStep "Waiting for Minio to be ready"
    if ! spinner_until 120 minio_ready; then
        bail "Minio API failed to report healthy"
    fi
    logSuccess "Minio is ready"
}

function minio_ready() {
    curl --noproxy "*" -s "http://${OBJECT_STORE_CLUSTER_IP}/minio/health/ready"
}

function minio_object_store_output() {
    # don't overwrite rook if also running
    if object_store_exists; then
        return 0;
    fi

    export OBJECT_STORE_ACCESS_KEY=
    export OBJECT_STORE_SECRET_KEY=
    export OBJECT_STORE_CLUSTER_IP=
    export OBJECT_STORE_CLUSTER_HOST=

    # create the docker-registry bucket through the S3 API
    OBJECT_STORE_ACCESS_KEY="$(kubectl -n ${MINIO_NAMESPACE} get secret minio-credentials -ojsonpath='{ .data.MINIO_ACCESS_KEY }' | base64 --decode)"
    OBJECT_STORE_SECRET_KEY="$(kubectl -n ${MINIO_NAMESPACE} get secret minio-credentials -ojsonpath='{ .data.MINIO_SECRET_KEY }' | base64 --decode)"
    OBJECT_STORE_CLUSTER_IP="$(kubectl -n ${MINIO_NAMESPACE} get service minio | tail -n1 | awk '{ print $3}')"
    OBJECT_STORE_CLUSTER_HOST="http://minio.${MINIO_NAMESPACE}"
}
