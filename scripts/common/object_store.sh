# shellcheck disable=SC2148
function object_store_exists() {
    if [ -n "$OBJECT_STORE_ACCESS_KEY" ] && \
        [ -n "$OBJECT_STORE_SECRET_KEY" ] && \
        [ -n "$OBJECT_STORE_CLUSTER_IP" ]; then
        return 0
    else
        return 1
    fi
}

function object_store_running() {
    if kubernetes_resource_exists rook-ceph secret rook-ceph-object-user-rook-ceph-store-kurl || kubernetes_resource_exists minio get secret minio-credentials; then
        return 0
    fi
    return 1
}

function object_store_create_bucket() {
    if object_store_bucket_exists "$1" ; then
        echo "object store bucket $1 exists"
        return 0
    fi
    if ! _object_store_create_bucket "$1" ; then
        if object_store_exists; then
          return 1
        fi
        bail "attempted to create bucket $1 but no object store configured"
    fi
    echo "object store bucket $1 created"
}

function _object_store_create_bucket() {
    local bucket=$1
    local acl="x-amz-acl:private"
    local d=$(LC_TIME="en_US.UTF-8" TZ="UTC" date +"%a, %d %b %Y %T %z")
    local string="PUT\n\n\n${d}\n${acl}\n/$bucket"
    local sig=$(echo -en "${string}" | openssl sha1 -hmac "${OBJECT_STORE_SECRET_KEY}" -binary | base64)

    local addr=$($DIR/bin/kurl netutil format-ip-address "$OBJECT_STORE_CLUSTER_IP")
    curl -fsSL -X PUT  \
        --globoff \
        --noproxy "*" \
        -H "Host: $OBJECT_STORE_CLUSTER_IP" \
        -H "Date: $d" \
        -H "$acl" \
        -H "Authorization: AWS $OBJECT_STORE_ACCESS_KEY:$sig" \
        "http://$addr/$bucket" >/dev/null 2>&1
}

function object_store_bucket_exists() {
    local bucket=$1
    local acl="x-amz-acl:private"
    local d=$(LC_TIME="en_US.UTF-8" TZ="UTC" date +"%a, %d %b %Y %T %z")
    local string="HEAD\n\n\n${d}\n${acl}\n/$bucket"
    local sig=$(echo -en "${string}" | openssl sha1 -hmac "${OBJECT_STORE_SECRET_KEY}" -binary | base64)

    local addr=$($DIR/bin/kurl netutil format-ip-address "$OBJECT_STORE_CLUSTER_IP")
    curl -fsSL -I \
        --globoff \
        --noproxy "*" \
        -H "Host: $OBJECT_STORE_CLUSTER_IP" \
        -H "Date: $d" \
        -H "$acl" \
        -H "Authorization: AWS $OBJECT_STORE_ACCESS_KEY:$sig" \
        "http://$addr/$bucket" >/dev/null 2>&1
}

# migrate_object_store creates a pod that migrates data between two different object stores. receives
# the namespace, the source and destination addresses, access keys and secret keys. returns once the
# pos has been finished or a timeout of 30 minutes has been reached.
function migrate_object_store() {
    local namespace=$1
    local source_addr=$2
    local source_access_key=$3
    local source_secret_key=$4
    local destination_addr=$5
    local destination_access_key=$6
    local destination_secret_key=$7

    kubectl -n "$namespace" delete pod sync-object-store --force --grace-period=0 --ignore-not-found

    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: sync-object-store
  namespace: ${namespace}
spec:
  restartPolicy: OnFailure
  containers:
  - name: sync-object-store
    image: $KURL_UTIL_IMAGE
    command:
    - /usr/local/bin/kurl
    - object-store
    - sync
    - --source_host=$source_addr
    - --source_access_key_id=$source_access_key
    - --source_access_key_secret=$source_secret_key
    - --dest_host=$destination_addr
    - --dest_access_key_id=$destination_access_key
    - --dest_access_key_secret=$destination_secret_key
EOF

    log "Waiting up to 5 minutes for sync-object-store pod to start in ${namespace} namespace"
    if ! spinner_until 300 kubernetes_pod_started sync-object-store "$namespace" ; then
        logFail "Failed to start object store migration pod within 5 minutes"
        return 1
    fi

    # The 10 minute spinner allows the pod to crash a few times waiting for the object store to be ready
    # and then following the logs allows for an indefinite amount of time for the migration to
    # complete in case there is a lot of data
    log "Waiting up to 10 minutes for sync-object-store pod to complete"
    if ! spinner_until 600 kubernetes_pod_completed sync-object-store "$namespace" ; then
        logWarn "Timeout faced waiting for start object store migration pod within 10 minutes"
    fi
    # this command intentionally tails the logs until the pod completes to get the full logs
    kubectl logs -n "$namespace" -f sync-object-store || true
    if kubernetes_pod_succeeded sync-object-store "$namespace" ; then
        logSuccess "Object store data synced successfully"
        kubectl delete pod sync-object-store -n "$namespace" --force --grace-period=0 &> /dev/null
        return 0
    fi

    return 1
}

function migrate_between_object_stores() {
    local source_host=$1
    local source_access_key=$2
    local source_secret_key=$3
    local destination_host=$4
    local destination_addr=$5
    local destination_access_key=$6
    local destination_secret_key=$7

    if kubernetes_resource_exists kurl deployment ekc-operator; then
        kubectl -n kurl scale deploy ekc-operator --replicas=0
        log "Waiting for ekco pods to be removed"
        if ! spinner_until 120 ekco_pods_gone; then
             logFail "Unable to scale down ekco operator"
             return 1
        fi
    fi

    get_shared

    if ! migrate_object_store "default" "$source_host" "$source_access_key" "$source_secret_key" "$destination_host" "$destination_access_key" "$destination_secret_key" ; then
        # even if the migration failed, we need to ensure ekco is running again
        if kubernetes_resource_exists kurl deployment ekc-operator; then
            kubectl -n kurl scale deploy ekc-operator --replicas=1
        fi
        bail "sync-object-store pod failed"
    fi

    # ensure ekco is running again
    if kubernetes_resource_exists kurl deployment ekc-operator; then
        kubectl -n kurl scale deploy ekc-operator --replicas=1
    fi

    # Update kotsadm to use new object store
    if kubernetes_resource_exists default secret kotsadm-s3; then
        echo "Updating kotsadm to use $destination_host"
        kubectl patch secret kotsadm-s3 -p "{\"stringData\":{\"access-key-id\":\"${destination_access_key}\",\"secret-access-key\":\"${destination_secret_key}\",\"endpoint\":\"http://${destination_host}\",\"object-store-cluster-ip\":\"${destination_addr}\"}}"

        if kubernetes_resource_exists default deployment kotsadm; then
            kubectl rollout restart deployment kotsadm
        elif kubernetes_resource_exists default statefulset kotsadm; then
            kubectl rollout restart statefulset kotsadm
        fi
    fi

    local newIP=$($DIR/bin/kurl netutil format-ip-address "$destination_addr")
    # Update registry to use new object store
    if kubernetes_resource_exists kurl configmap registry-config; then
        echo "Updating registry to use $destination_host"
        local temp_file=
        temp_file=$(mktemp)
        kubectl -n kurl get configmap registry-config -ojsonpath='{ .data.config\.yml }' | sed "s/regionendpoint: http.*/regionendpoint: http:\/\/${newIP}/" > "$temp_file"
        kubectl -n kurl delete configmap registry-config
        kubectl -n kurl create configmap registry-config --from-file=config.yml="$temp_file"
        rm "$temp_file"
    fi
    if kubernetes_resource_exists kurl secret registry-s3-secret; then
        kubectl -n kurl patch secret registry-s3-secret -p "{\"stringData\":{\"access-key-id\":\"${destination_access_key}\",\"secret-access-key\":\"${destination_secret_key}\",\"object-store-cluster-ip\":\"${destination_addr}\",\"object-store-hostname\":\"http://${destination_host}\"}}"
    fi
    if kubernetes_resource_exists kurl deployment registry; then
        kubectl -n kurl rollout restart deployment registry
    fi

    # Update velero to use new object store only if currently using object store since velero may have already been
    # updated to use an off-cluster object store.
    if kubernetes_resource_exists velero backupstoragelocation default; then
        echo "Updating velero to use new object store $destination_host"
        s3Url=$(kubectl -n velero get backupstoragelocation default -ojsonpath='{ .spec.config.s3Url }')
        if [ "$s3Url" = "http://${source_host}" ]; then
            kubectl -n velero patch backupstoragelocation default --type=merge -p "{\"spec\":{\"config\":{\"s3Url\":\"http://${destination_host}\",\"publicUrl\":\"http://${newIP}\"}}}"

            while read -r resticrepo; do
                oldResticIdentifier=$(kubectl -n velero get resticrepositories "$resticrepo" -ojsonpath="{ .spec.resticIdentifier }")
                newResticIdentifier=$(echo "$oldResticIdentifier" | sed "s/${source_host}/${destination_host}/")
                kubectl -n velero patch resticrepositories "$resticrepo" --type=merge -p "{\"spec\":{\"resticIdentifier\":\"${newResticIdentifier}\"}}"
            done < <(kubectl -n velero get resticrepositories --selector=velero.io/storage-location=default --no-headers | awk '{ print $1 }')
        else
            echo "The Velero default backupstoragelocation was not $source_host, not updating to use $destination_host"
        fi
    fi
    if kubernetes_resource_exists velero secret cloud-credentials; then
        if kubectl -n velero get secret cloud-credentials -ojsonpath='{ .data.cloud }' | base64 -d | grep -q "$source_access_key"; then
            local temp_file=
            temp_file=$(mktemp)
            kubectl -n velero get secret cloud-credentials -ojsonpath='{ .data.cloud }' | base64 -d > "$temp_file"
            sed -i "s/aws_access_key_id=.*/aws_access_key_id=${destination_access_key}/" "$temp_file"
            sed -i "s/aws_secret_access_key=.*/aws_secret_access_key=${destination_secret_key}/" "$temp_file"
            cloud=$(cat "$temp_file" | base64 -w 0)
            kubectl -n velero patch secret cloud-credentials -p "{\"data\":{\"cloud\":\"${cloud}\"}}"
            rm "$temp_file"
        else
            echo "The Velero cloud-credentials secret did not contain credentials for $source_host, not updating to use $destination_host credentials"
        fi
    fi
    if kubernetes_resource_exists velero daemonset restic; then
        kubectl -n velero rollout restart daemonset restic
    fi
    if kubernetes_resource_exists velero deployment velero; then
        kubectl -n velero rollout restart deployment velero
    fi

    printf "\n${GREEN}Object store migration completed successfully${NC}\n"

    return 0
}

function migrate_rgw_to_minio_checks() {
    logStep "Running Object Store from Rook to Minio migration checks ..."

    if ! rook_is_health_to_upgrade; then
        bail "Cannot upgrade from Rook ObjectStore to Minio due it is unhealthy."
    fi

    log "Awaiting to check if rook-ceph object store is health"
    if ! spinner_until 300 rook_rgw_is_healthy ; then
        logFail "Failed to detect healthy rook-ceph object store"
        bail "Cannot upgrade from Rook ObjectStore to Minio due it is unhealthy."
    fi

    logSuccess "Object Store from Rook to Minio migration checks completed."
}

function rook_rgw_is_healthy() {
    export OBJECT_STORE_CLUSTER_IP
    OBJECT_STORE_CLUSTER_IP=$(kubectl -n rook-ceph get service rook-ceph-rgw-rook-ceph-store | tail -n1 | awk '{ print $3}')
    export OBJECT_STORE_CLUSTER_HOST="http://rook-ceph-rgw-rook-ceph-store.rook-ceph"
    # same as OBJECT_STORE_CLUSTER_IP for IPv4, wrapped in brackets for IPv6
    export OBJECT_STORE_CLUSTER_IP_BRACKETED
    OBJECT_STORE_CLUSTER_IP_BRACKETED=$("$DIR"/bin/kurl netutil format-ip-address "$OBJECT_STORE_CLUSTER_IP")
    curl --globoff --noproxy "*" --fail --silent --insecure "http://${OBJECT_STORE_CLUSTER_IP_BRACKETED}" > /dev/null
}

function migrate_rgw_to_minio() {
    report_addon_start "rook-ceph-to-minio" "v1.1"

    migrate_rgw_to_minio_checks

    RGW_HOST="rook-ceph-rgw-rook-ceph-store.rook-ceph"
    RGW_ACCESS_KEY_ID=$(kubectl -n rook-ceph get secret rook-ceph-object-user-rook-ceph-store-kurl -o yaml | grep AccessKey | head -1 | awk '{print $2}' | base64 --decode)
    RGW_ACCESS_KEY_SECRET=$(kubectl -n rook-ceph get secret rook-ceph-object-user-rook-ceph-store-kurl -o yaml | grep SecretKey | head -1 | awk '{print $2}' | base64 --decode)

    MINIO_HOST="minio.${MINIO_NAMESPACE}"
    MINIO_CLUSTER_IP=$(kubectl -n ${MINIO_NAMESPACE} get service minio | tail -n1 | awk '{ print $3}')
    MINIO_ACCESS_KEY_ID=$(kubectl -n ${MINIO_NAMESPACE} get secret minio-credentials -ojsonpath='{ .data.MINIO_ACCESS_KEY }' | base64 --decode)
    MINIO_ACCESS_KEY_SECRET=$(kubectl -n ${MINIO_NAMESPACE} get secret minio-credentials -ojsonpath='{ .data.MINIO_SECRET_KEY }' | base64 --decode)

    migrate_between_object_stores "$RGW_HOST" "$RGW_ACCESS_KEY_ID" "$RGW_ACCESS_KEY_SECRET" "$MINIO_HOST" "$MINIO_CLUSTER_IP" "$MINIO_ACCESS_KEY_ID" "$MINIO_ACCESS_KEY_SECRET"

    report_addon_success "rook-ceph-to-minio" "v1.1"
}

function migrate_minio_to_rgw() {
    local minio_ns="$MINIO_NAMESPACE"
    if [ -z "$minio_ns" ]; then
        minio_ns=minio
    fi

    if ! kubernetes_resource_exists $minio_ns deployment minio; then
        return 0
    fi

    report_addon_start "minio-to-rook-ceph" "v1.1"

    MINIO_HOST="minio.${minio_ns}"
    MINIO_ACCESS_KEY_ID=$(kubectl -n ${minio_ns} get secret minio-credentials -ojsonpath='{ .data.MINIO_ACCESS_KEY }' | base64 --decode)
    MINIO_ACCESS_KEY_SECRET=$(kubectl -n ${minio_ns} get secret minio-credentials -ojsonpath='{ .data.MINIO_SECRET_KEY }' | base64 --decode)

    RGW_HOST="rook-ceph-rgw-rook-ceph-store.rook-ceph"
    RGW_CLUSTER_IP=$(kubectl -n rook-ceph get service rook-ceph-rgw-rook-ceph-store | tail -n1 | awk '{ print $3}')
    RGW_ACCESS_KEY_ID=$(kubectl -n rook-ceph get secret rook-ceph-object-user-rook-ceph-store-kurl -o yaml | grep AccessKey | head -1 | awk '{print $2}' | base64 --decode)
    RGW_ACCESS_KEY_SECRET=$(kubectl -n rook-ceph get secret rook-ceph-object-user-rook-ceph-store-kurl -o yaml | grep SecretKey | head -1 | awk '{print $2}' | base64 --decode)

    migrate_between_object_stores "$MINIO_HOST" "$MINIO_ACCESS_KEY_ID" "$MINIO_ACCESS_KEY_SECRET" "$RGW_HOST" "$RGW_CLUSTER_IP" "$RGW_ACCESS_KEY_ID" "$RGW_ACCESS_KEY_SECRET"

    report_addon_success "minio-to-rook-ceph" "v1.1"
}
