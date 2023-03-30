DID_MIGRATE_ROOK_OBJECT_STORE=

function minio_pre_init() {
    if [ -z "$MINIO_NAMESPACE" ]; then
        MINIO_NAMESPACE=minio
    fi

    if [ -z "$MINIO_CLAIM_SIZE" ]; then
        MINIO_CLAIM_SIZE="10Gi"
    fi

    # verify if we need to migrate away from the deprecated 'fs' format.
    local minio_replicas
    minio_replicas=$(kubectl get deploy minio -n "$MINIO_NAMESPACE" -o template="{{.spec.replicas}}" 2>/dev/null || true)
    if [ -n "$minio_replicas" ] && [ "$minio_replicas" != "0" ] && minio_uses_fs_format ; then
        printf "${YELLOW}\n"
        printf "The installer has detected that the cluster is running a version of minio backed by the now legacy FS format.\n"
        printf "To be able to upgrade to the new Minio version a migration will be necessary. During this migration, Minio\n"
        printf "will be unavailable.\n"
        printf "\n"
        printf "For further information please check https://github.com/minio/minio/releases/tag/RELEASE.2022-10-29T06-21-33Z\n"
        printf "${NC}\n"
        printf "Would you like to proceed with the migration ?"
        if ! confirmN; then
            bail "Not migrating"
        fi

        if ! minio_has_enough_space_for_fs_migration ; then
            bail "Not enough disk space found for minio migration."
        fi
    fi
}

function minio() {
    local src="$DIR/addons/minio/2023-01-02T09-40-09Z"
    local dst="$DIR/kustomize/minio"

    minio_migrate_fs_backend

    local minio_ha_exists=
    if kubectl get statefulset -n minio ha-minio 2>/dev/null; then
        minio_ha_exists=1
    fi

    if [ -n "$minio_ha_exists" ]; then
        # don't update the statefulset or deployment, just change the images they use
        kubectl set image -n minio statefulset/ha-minio minio=minio/minio:RELEASE.2023-01-02T09-40-09Z

        # the deployment will have been deleted if data has been migrated to the statefulset, so don't error if the image isn't updated
        kubectl set image -n minio deployment/minio minio=minio/minio:RELEASE.2023-01-02T09-40-09Z 2>/dev/null || true
    else
        # create the statefulset/deployment/service/secret/etc
        render_yaml_file_2 "$src/tmpl-kustomization.yaml" > "$dst/kustomization.yaml"
        render_yaml_file_2 "$src/tmpl-namespace.yaml" > "$dst/namespace.yaml"

        if [ -n "$OPENEBS_LOCALPV" ]; then
            # only create the statefulset if localpv is enabled for it to use
            render_yaml_file_2 "$src/tmpl-ha-statefulset.yaml" > "$dst/ha-statefulset.yaml"
            insert_resources "$dst/kustomization.yaml" "ha-statefulset.yaml"
        fi

        cp "$src/deployment.yaml" "$dst/"
        cp "$src/service.yaml" "$dst/"

        if [ -n "$MINIO_HOSTPATH" ]; then
            render_yaml_file_2 "$src/tmpl-deployment-hostpath.yaml" > "$dst/deployment-hostpath.yaml"
            insert_patches_strategic_merge "$dst/kustomization.yaml" deployment-hostpath.yaml
        else
            render_yaml_file_2 "$src/tmpl-pvc.yaml" > "$dst/pvc.yaml"
            insert_resources "$dst/kustomization.yaml" pvc.yaml
            render_yaml_file_2 "$src/tmpl-deployment-pvc.yaml" > "$dst/deployment-pvc.yaml"
            insert_patches_strategic_merge "$dst/kustomization.yaml" deployment-pvc.yaml
        fi

        minio_creds "$src" "$dst"

        kubectl apply -k "$dst/"
    fi

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

    render_yaml_file_2 "$src/tmpl-creds-secret.yaml" > "$dst/creds-secret.yaml"
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
    if ! spinner_until 120 minio_ready "$MINIO_CLUSTER_IP" ; then
        bail "Minio API failed to report healthy"
    fi
    printf "awaiting minio endpoint\n"
    if ! spinner_until 120 minio_endpoint_exists; then
        bail "Minio endpoint failed to be discovered"
    fi
}

function minio_ready() {
    local minio_cluster_ip=$1
    curl --noproxy "*" -s "http://$minio_cluster_ip/minio/health/ready"
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

    log "Check if object store was migrated previously"
    export DID_MIGRATE_ROOK_OBJECT_STORE=0
    DID_MIGRATE_ROOK_OBJECT_STORE=$(kubectl -n kurl get --ignore-not-found configmap kurl-migration-from-rook -o jsonpath='{ .data.DID_MIGRATE_ROOK_OBJECT_STORE }')
    if [ "$DID_MIGRATE_ROOK_OBJECT_STORE" == "1" ]; then
        logWarn "Object store is set as migrated previously. Not migrating object store again."
        return
    fi

    migrate_rgw_to_minio
    add_rook_store_object_migration_status
}

# TODO: allow this to work with the HA statefulset
function allow_pvc_resize() {
    if kubernetes_resource_exists "$MINIO_NAMESPACE" pvc minio-pv-claim; then
        # check if the minio PVC's current size is not the desired size
        current_size=$(kubectl get pvc -n "$MINIO_NAMESPACE" minio-pv-claim -o jsonpath='{.status.capacity.storage}')
        desired_size=$(kubectl get pvc -n "$MINIO_NAMESPACE" minio-pv-claim -o jsonpath='{.spec.resources.requests.storage}')
        current_scale=$(kubectl get deployment -n "$MINIO_NAMESPACE" minio -o jsonpath='{.spec.replicas}')

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

            # restore the scale (whether the minute of waiting worked or not)
            kubectl scale deployment -n "$MINIO_NAMESPACE" minio --replicas="$current_scale"
        fi
    fi
}

# minio_ask_user_hostpath_for_migration asks uses for a path to be used during the minio host path migration.
# this path can't be the same or a subdirectory of MINIO_HOSTPATH. this function ensures that the migration path
# has enough space to host the data being migrated over.
function minio_ask_user_hostpath_for_migration() {
    printf "${YELLOW}\n"
    printf "The Minio deployment is using a host path mount (volume from the node mounted inside the pod). For the\n"
    printf "migration to proceed you must provide the installer with a temporary directory path, this path will be\n"
    printf "used only during the migration and will be freed after.\n"
    printf "${NC}\n"

    local space_needed
    space_needed=$(du -sB1 "$MINIO_HOSTPATH" | cut -f1)
    if [ -z "$space_needed" ]; then
        bail "Failed to calculate how much space is in use by Minio"
    fi

    while true; do
        printf "Temporary migration directory path: "
        prompt

        local migration_path
        migration_path=$(realpath "$PROMPT_RESULT")
        if [ -z "$migration_path" ]; then
            continue
        fi

        if [ ! -d "$migration_path" ]; then
            printf "%s is not a directory\n" "$PROMPT_RESULT"
            continue
        fi

        if [[ $migration_path == $MINIO_HOSTPATH/* ]]; then
            printf "Migration directory path can not be a subdirectory of %s\n" "$MINIO_HOSTPATH"
            continue
        fi

        if [ "$migration_path" = "$MINIO_HOSTPATH" ]; then
            printf "%s is currently in use by Minio\n" "$MINIO_HOSTPATH"
            continue
        fi

        printf "Analyzing free disk space on %s\n" "$migration_path"
        local free_space_cmd_output
        free_space_cmd_output=$(df -B1 --output=avail "$migration_path" 2>&1)

        local free_space
        free_space=$(echo "$free_space_cmd_output" | tail -1)
        if [ -z "$free_space" ]; then
            printf "Failed to verify the amount of free disk space under %s\n" "$migration_path"
            printf "Command output:\n%s\n" "$free_space_cmd_output"
            continue
        fi

        if [ "$space_needed" -gt "$free_space" ]; then
            printf "Not enough space to migrate %s bytes from %s to %s\n" "$space_needed" "$MINIO_HOSTPATH" "$migration_path"
            continue
        fi

        break
    done

    local suffix
    suffix=$(echo $RANDOM | md5sum | head -c 8)
    local migration_path
    migration_path=$(printf "%s/minio-migration-%s" "$PROMPT_RESULT" "$suffix")
    mkdir "$migration_path"
    MINIO_MIGRATION_HOSTPATH=$migration_path
}

# minio_create_fs_migration_deployment creates a minio deployment and make it available through a service called
# 'minio-migrate-fs-backend'. this new deployment uses the same credentials used by the original minio
# deployment. if the installation uses host path and not a pvc, a temporary path is requested from the user.
function minio_create_fs_migration_deployment() {
    local src="$DIR/addons/minio/2023-01-02T09-40-09Z/migrate-fs"
    local dst="$DIR/kustomize/minio/migrate-fs"

    if [ -n "$MINIO_HOSTPATH" ]; then
        mkdir -p "$dst/hostpath"
        render_yaml_file_2 "$src/hostpath/deployment.yaml" > "$dst/hostpath/deployment.yaml"
        render_yaml_file_2 "$src/hostpath/kustomization.yaml" > "$dst/hostpath/kustomization.yaml"
        render_yaml_file_2 "$src/hostpath/service.yaml" > "$dst/hostpath/service.yaml"
        render_yaml_file_2 "$src/hostpath/original-service.yaml" > "$dst/hostpath/original-service.yaml"
        kubectl apply -k "$dst/hostpath/"
    else
        mkdir -p "$dst/pvc"
        render_yaml_file_2 "$src/pvc/deployment.yaml" > "$dst/pvc/deployment.yaml"
        render_yaml_file_2 "$src/pvc/kustomization.yaml" > "$dst/pvc/kustomization.yaml"
        render_yaml_file_2 "$src/pvc/service.yaml" > "$dst/pvc/service.yaml"
        render_yaml_file_2 "$src/pvc/pvc.yaml" > "$dst/pvc/pvc.yaml"
        render_yaml_file_2 "$src/pvc/original-service.yaml" > "$dst/pvc/original-service.yaml"
        kubectl apply -k "$dst/pvc/"
    fi

    local endpoint
    endpoint=$(kubectl -n "$MINIO_NAMESPACE" get service minio-migrate-fs-backend -o template="{{.spec.clusterIP}}" 2>/dev/null)
    if [ -z "$endpoint" ]; then
        bail "Failed to determine endpoint for the minio migration deployment"
    fi

    printf "Awaiting minio fs migration readiness\n"
    if ! spinner_until 300 minio_ready "$endpoint"; then
        bail "Minio FS Migration API failed to report healthy"
    fi

    endpoint=$(kubectl -n "$MINIO_NAMESPACE" get service original-minio -o template="{{.spec.clusterIP}}" 2>/dev/null)
    if [ -z "$endpoint" ]; then
        bail "Failed to determine the ip address for the minio temporary service"
    fi

    printf "Awaiting minio readiness through the temporary service\n"
    if ! spinner_until 300 minio_ready "$endpoint"; then
        bail "Minio API failed to report healthy"
    fi
}

# minio_destroy_fs_migration_deployment deletes the temporary minio deployment used to migrate the object
# storage.
function minio_destroy_fs_migration_deployment() {
    local dst="$DIR/kustomize/minio/migrate-fs"
    if [ -n "$MINIO_HOSTPATH" ]; then
        kubectl delete -k "$dst/hostpath"
        return
    fi
    kubectl delete -k "$dst/pvc"
}

# minio_swap_fs_migration_pvs swaps the pv backing the minio deployment with the pv used during the migration.
function minio_swap_fs_migration_pvs() {
    local minio_pv=$1
    local migration_pv=$2
    local src="$DIR/addons/minio/2023-01-02T09-40-09Z"
    local dst="$DIR/kustomize/minio"

    MINIO_ORIGINAL_CLAIM_SIZE=$(kubectl get pvc -n "$MINIO_NAMESPACE" minio-pv-claim -o template="{{.spec.resources.requests.storage}}" 2>/dev/null)
    if [ -z "$MINIO_ORIGINAL_CLAIM_SIZE" ]; then
        MINIO_ORIGINAL_CLAIM_SIZE="$MINIO_CLAIM_SIZE"
    fi

    kubectl patch pv "$migration_pv" --type=json -p='[{"op": "remove", "path": "/spec/claimRef"}]'
    kubectl delete pvc -n "$MINIO_NAMESPACE" minio-pv-claim
    kubectl patch pv "$minio_pv" --type=json -p='[{"op": "remove", "path": "/spec/claimRef"}]'

    printf "${YELLOW}A backup of the original Minio data has been stored in PersistentVolumeClaim minio-pv-claim-backup${NC}\n"

    MINIO_NEW_VOLUME_NAME="$migration_pv"
    MINIO_ORIGINAL_VOLUME_NAME="$minio_pv"
    render_yaml_file_2 "$src/migrate-fs/minio-pvc.yaml" > "$dst/migrate-fs/minio-pvc.yaml"
    kubectl create -f "$dst/migrate-fs/minio-pvc.yaml"
    render_yaml_file_2 "$src/migrate-fs/minio-backup-pvc.yaml" > "$dst/migrate-fs/minio-backup-pvc.yaml"
    kubectl create -f "$dst/migrate-fs/minio-backup-pvc.yaml"
}

# minio_swap_fs_migration_hostpaths moves the host path used during the migration to the host path used by the
# original minio pod. a backup is kept under hostpath.bkp directory.
function minio_swap_fs_migration_hostpaths() {
    local suffix
    local bkp_location
    suffix=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c8)
    bkp_location=$(printf "%s-%s" "$MINIO_HOSTPATH" "$suffix")
    mv "$MINIO_HOSTPATH" "$bkp_location"
    printf "${YELLOW}A backup of the original Minio data has been stored at %s${NC}\n" "$bkp_location"

    mv "$MINIO_MIGRATION_HOSTPATH" "$MINIO_HOSTPATH"
    cp -Rfp "$bkp_location/.kurl" "$MINIO_HOSTPATH/"
}

# minio_uses_fs_format verifies if minio uses the legacy fs format. greps the file /data/.minio.sys/format.json
# from within the pod.
function minio_uses_fs_format() {
    # before running this we need to ensure that the minio deployment is fully deployed.
    printf "Awaiting for minio deployment to rollout\n"
    if ! spinner_until 300 deployment_fully_updated minio "$MINIO_NAMESPACE"; then
        bail "Timeout awaiting for minio deployment"
    fi

    printf "Getting Minio storage format\n"
    for i in $(seq 1 300); do
        local format_string
        format_string=$(kubectl exec -n $MINIO_NAMESPACE deploy/minio -- cat /data/.minio.sys/format.json 2>/dev/null)
        if [ -z "$format_string" ]; then
            sleep 1
            continue
        fi

        if echo "$format_string" | grep -q '"format":"fs"'; then
            return 0
        fi
        return 1
    done
    bail "Failed to read /data/.minio.sys/format.json inside minio pod"
}

# minio_svc_has_no_endpoints validates that the provided service in the provided namespace has no endpoints.
function minio_svc_has_no_endpoints() {
    local namespace=$1
    local service=$2
    kubectl get endpoints -n "$namespace" "$service" -o template="{{.subsets}}" | grep -q "no value"
}

# minio_disable_minio_svc disables the minio service by tweaking its service selector.
function minio_disable_minio_svc() {
    kubectl patch svc -n "$MINIO_NAMESPACE" minio -p '{"spec":{"selector":{"app":"does-not-exist"}}}'
}

# minio_enable_minio_svc sets the minio service selector back to its default.
function minio_enable_minio_svc() {
    kubectl patch svc -n "$MINIO_NAMESPACE" minio -p '{"spec":{"selector":{"app":"minio"}}}'
}

# minio_prepare_volumes_for_migration sets the retention policy of the volumes to "retain" for both minio and its migration deployment.
function minio_prepare_volumes_for_migration() {
    local minio_pv=$1
    local migration_pv=$2
    # set both of the pv retention policies to 'retain'.
    kubectl patch pv -n "$MINIO_NAMESPACE" "$minio_pv" -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
    kubectl patch pv -n "$MINIO_NAMESPACE" "$migration_pv" -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
}

# minio_has_enough_space_for_fs_migration verifies if there is enough disk space in the cluster to execute the migration.
function minio_has_enough_space_for_fs_migration() {
    if [ -n "$MINIO_HOSTPATH" ]; then
        minio_ask_user_hostpath_for_migration
        return 0
    fi
    "$DIR"/bin/kurl cluster check-free-disk-space --debug --openebs-image "$KURL_UTIL_IMAGE" --bigger-than "$MINIO_CLAIM_SIZE" 2>&1
}


# minio_pods_are_finished returns 0 when there is no more pods with label app=minio in the minio namespace.
function minio_pods_are_finished() {
    local pods
    pods="$(kubectl -n "$MINIO_NAMESPACE" get pods --no-headers -l app=minio 2>/dev/null)"
    if [ "$?" != "0" ]; then
        return 1
    fi

    local pods_count
    pods_count="$(echo -n "$pods" | wc -l)"
    if [ "$pods_count" -eq "0" ]; then
        return 0
    fi

    return 1
}

# minio_restore_original_deployment re-enables the original minio service, scales up the original minio deployment and destroy
# the fs migration deployment.
function minio_restore_original_deployment() {
    local minio_replicas="$1"
    minio_enable_minio_svc || true
    minio_destroy_fs_migration_deployment || true
    kubectl scale deployment -n "$MINIO_NAMESPACE" minio --replicas="$minio_replicas" || true
}

# minio_migrate_fs_backend migrates a minio running with 'fs' backend into the new default backend type (xl). spawns a new
# minio deployment then copies the object buckets from the old deployment into the new one. this function generates
# unavailability of the original minio service.
function minio_migrate_fs_backend() {
    local minio_replicas
    minio_replicas=$(kubectl get deploy minio -n "$MINIO_NAMESPACE" -o template="{{.spec.replicas}}" 2>/dev/null || true)
    if [ -z "$minio_replicas" ] || [ "$minio_replicas" = "0" ] || ! minio_uses_fs_format ; then
        return
    fi

    # we need to guarantee that the minio is working before starting to migrate. i have seen cases where due to the upgrade
    # logic some pods take a while to come back up and, especially, receive an ip address. let's first make sure we can
    # reach minio and then move forward. best case scenario we will move forward immediately, worst case scenario we fail
    # because we can't reach minio (we would fail anyways).
    local minio_service_ip
    minio_service_ip=$(kubectl -n "$MINIO_NAMESPACE" get service minio -o template="{{.spec.clusterIP}}" 2>/dev/null)
    if [ -z "$minio_service_ip" ]; then
        bail "Failed to determine minio service ip address"
    fi

    printf "Awaiting installed minio readiness\n"
    if ! spinner_until 300 minio_ready "$minio_service_ip" ; then
        bail "Minio API failed to report healthy"
    fi

    local minio_access_key
    minio_access_key=$(kubernetes_secret_value "$MINIO_NAMESPACE" minio-credentials MINIO_ACCESS_KEY)
    if [ -z "$minio_access_key" ]; then
        bail "Failed to read minio access key"
    fi

    local minio_secret_key
    minio_secret_key=$(kubernetes_secret_value "$MINIO_NAMESPACE" minio-credentials MINIO_SECRET_KEY)
    if [ -z "$minio_secret_key" ]; then
        bail "Failed to read minio access key"
    fi

    minio_disable_minio_svc
    if ! spinner_until 300 minio_svc_has_no_endpoints "$MINIO_NAMESPACE" "minio" ; then
        minio_enable_minio_svc
        bail "Timeout waiting for minio service to be decomissioned"
    fi

    if ! minio_create_fs_migration_deployment ; then
        minio_enable_minio_svc
        bail "Failed to start minio migration deployment"
    fi

    if ! migrate_object_store \
        "$MINIO_NAMESPACE" \
        "original-minio" \
        "$minio_access_key" \
        "$minio_secret_key" \
        "minio-migrate-fs-backend" \
        "$minio_access_key" \
        "$minio_secret_key"
    then
        minio_enable_minio_svc
        minio_destroy_fs_migration_deployment
        bail "Failed to migrate data to minio migration deployment"
    fi

    # scale down minio and wait until it is out of service.
    kubectl scale deployment -n "$MINIO_NAMESPACE" minio --replicas=0
    if ! spinner_until 300 deployment_fully_updated minio "$MINIO_NAMESPACE"; then
        minio_restore_original_deployment "$minio_replicas"
        bail "Timeout scaling down minio deployment"
    fi

    # wait until are minio pods have been completely stopped.
    if ! spinner_until 300 minio_pods_are_finished; then
        minio_restore_original_deployment "$minio_replicas"
        bail "Timeout waiting for minio pods to finish"
    fi

    if [ -z "$MINIO_HOSTPATH" ]; then
        # get the pv in use by the minio deployment, we gonna need it later on when we swap the pvs.
        local minio_pv
        minio_pv=$(kubectl get pvc -n "$MINIO_NAMESPACE" minio-pv-claim -o template="{{.spec.volumeName}}" 2>/dev/null)
        if [ -z "$minio_pv" ]; then
            minio_restore_original_deployment "$minio_replicas"
            bail "Failed to find minio pv"
        fi

        # get the pv in use by the fs migration deployment, we gonna need it later on when we swap the pvs.
        local migration_pv
        migration_pv=$(kubectl get pvc -n "$MINIO_NAMESPACE" minio-migrate-fs-backend-pv-claim -o template="{{.spec.volumeName}}" 2>/dev/null)
        if [ -z "$migration_pv" ]; then
            minio_restore_original_deployment "$minio_replicas"
            bail "Failed to find minio pv"
        fi

        if ! minio_prepare_volumes_for_migration "$minio_pv" "$migration_pv" ; then
            minio_restore_original_deployment "$minio_replicas"
            bail "Failed to prepare minio volumes for migration"
        fi
    fi

    minio_destroy_fs_migration_deployment

    # at this stage we have the data already migrated from the old minio into the new one. we now swap
    # the volumes. this procedure differs based on the type of storage used (hostpath/pvc).
    if [ -n "$MINIO_HOSTPATH" ]; then
        minio_swap_fs_migration_hostpaths
    else
        minio_swap_fs_migration_pvs "$minio_pv" "$migration_pv"
    fi

    # XXX scale minio back up with the same number of replicas. we can't wait for it to be healthy at this
    # stage because the old image does not support the new default backend type (xl). as the migration
    # moves on the image references are going to be replaced in the minio deployment and it will come back
    # online.
    kubectl -n "$MINIO_NAMESPACE" scale deployment minio --replicas="$minio_replicas"
    minio_enable_minio_svc
}
