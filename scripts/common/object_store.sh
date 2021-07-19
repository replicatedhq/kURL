
function object_store_exists() {
    if [ -n "$OBJECT_STORE_ACCESS_KEY" ] && \
        [ -n "$OBJECT_STORE_SECRET_KEY" ] && \
        [ -n "$OBJECT_STORE_CLUSTER_IP" ]; then
        return 0
    else
        return 1
    fi
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

    curl -fsSL -X PUT  \
        --noproxy "*" \
        -H "Host: $OBJECT_STORE_CLUSTER_IP" \
        -H "Date: $d" \
        -H "$acl" \
        -H "Authorization: AWS $OBJECT_STORE_ACCESS_KEY:$sig" \
        "http://$OBJECT_STORE_CLUSTER_IP/$bucket" >/dev/null 2>&1
}

function object_store_bucket_exists() {
    local bucket=$1
    local acl="x-amz-acl:private"
    local d=$(LC_TIME="en_US.UTF-8" TZ="UTC" date +"%a, %d %b %Y %T %z")
    local string="HEAD\n\n\n${d}\n${acl}\n/$bucket"
    local sig=$(echo -en "${string}" | openssl sha1 -hmac "${OBJECT_STORE_SECRET_KEY}" -binary | base64)

    curl -fsSL -I \
        --noproxy "*" \
        -H "Host: $OBJECT_STORE_CLUSTER_IP" \
        -H "Date: $d" \
        -H "$acl" \
        -H "Authorization: AWS $OBJECT_STORE_ACCESS_KEY:$sig" \
        "http://$OBJECT_STORE_CLUSTER_IP/$bucket" >/dev/null 2>&1
}

function migrate_rgw_to_minio() {
    RGW_HOST="rook-ceph-rgw-rook-ceph-store.rook-ceph"
    RGW_ACCESS_KEY_ID=$(kubectl -n rook-ceph get secret rook-ceph-object-user-rook-ceph-store-kurl -o yaml | grep AccessKey | head -1 | awk '{print $2}' | base64 --decode)
    RGW_ACCESS_KEY_SECRET=$(kubectl -n rook-ceph get secret rook-ceph-object-user-rook-ceph-store-kurl -o yaml | grep SecretKey | head -1 | awk '{print $2}' | base64 --decode)

    MINIO_HOST="minio.${MINIO_NAMESPACE}"
    MINIO_ACCESS_KEY_ID=$(kubectl -n ${MINIO_NAMESPACE} get secret minio-credentials -ojsonpath='{ .data.MINIO_ACCESS_KEY }' | base64 --decode)
    MINIO_ACCESS_KEY_SECRET=$(kubectl -n ${MINIO_NAMESPACE} get secret minio-credentials -ojsonpath='{ .data.MINIO_SECRET_KEY }' | base64 --decode)
    MINIO_CLUSTER_IP=$(kubectl -n ${MINIO_NAMESPACE} get service minio | tail -n1 | awk '{ print $3}')

    get_shared    

    kubectl delete pod sync-object-store --force --grace-period=0 &>/dev/null || true

    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: sync-object-store
  namespace: default
spec:
  restartPolicy: OnFailure
  containers:
  - name: sync-object-store
    image: $KURL_UTIL_IMAGE
    command:
    - /usr/local/bin/kurl
    - sync-object-store
    - --source_host=$RGW_HOST
    - --source_access_key_id=$RGW_ACCESS_KEY_ID
    - --source_access_key_secret=$RGW_ACCESS_KEY_SECRET
    - --dest_host=$MINIO_HOST
    - --dest_access_key_id=$MINIO_ACCESS_KEY_ID
    - --dest_access_key_secret=$MINIO_ACCESS_KEY_SECRET
EOF

    echo "Waiting up to 2 minutes for sync-object-store pod to start"
    if ! spinner_until 120 kubernetes_pod_started sync-object-store default; then
        bail "sync-object-store pod failed to start within 2 minutes"
    fi


    # The 5 minute spinner allows the pod to crash a few times waiting for minio to be ready
    # and then following the logs allows for an indefinite amount of time for the migration to
    # complete in case there is a lot of data
    echo "Waiting up to 5 minutes for sync-object-store pod to complete"
    spinner_until 300 kubernetes_pod_completed sync-object-store default
    kubectl logs -f sync-object-store

    if kubernetes_pod_succeeded sync-object-store default; then
        printf "\n${GREEN}Object store data synced successfully${NC}\n"
        kubectl delete pod sync-object-store --force --grace-period=0 &> /dev/null
    else
        bail "sync-object-store pod failed"
    fi

    # Update kotsadm to use minio
    if kubernetes_resource_exists default secret kotsadm-s3; then
        echo "Updating kotsadm to use minio"
        kubectl patch secret kotsadm-s3 -p "{\"stringData\":{\"access-key-id\":\"${MINIO_ACCESS_KEY_ID}\",\"secret-access-key\":\"${MINIO_ACCESS_KEY_SECRET}\",\"endpoint\":\"http://${MINIO_HOST}\",\"object-store-cluster-ip\":\"${MINIO_CLUSTER_IP}\"}}"

        if kubernetes_resource_exists default deployment kotsadm; then
            kubectl rollout restart deployment kotsadm
        elif kubernetes_resource_exists default statefulset kotsadm; then
            kubectl rollout restart statefulset kotsadm
        fi
    fi

    # Update registry to use minio
    if kubernetes_resource_exists kurl configmap registry-config; then
        echo "Updating registry to use minio"
        kubectl -n kurl get configmap registry-config -ojsonpath='{ .data.config\.yml }' | sed "s/regionendpoint: http.*/regionendpoint: http:\/\/${MINIO_CLUSTER_IP}/" > config.yml
        kubectl -n kurl delete configmap registry-config
        kubectl -n kurl create configmap registry-config --from-file=config.yml=config.yml
        rm config.yml
    fi
    if kubernetes_resource_exists kurl secret registry-s3-secret; then
        kubectl -n kurl patch secret registry-s3-secret -p "{\"stringData\":{\"access-key-id\":\"${MINIO_ACCESS_KEY_ID}\",\"secret-access-key\":\"${MINIO_ACCESS_KEY_SECRET}\",\"object-store-cluster-ip\":\"${MINIO_CLUSTER_IP}\"}}"
    fi
    if kubernetes_resource_exists kurl deployment registry; then
        kubectl -n kurl rollout restart deployment registry
    fi

    # Update velero to use minio only if currently using RGW since velero may have already been
    # updated to use an off-cluster object store.
    if kubernetes_resource_exists velero backupstoragelocation default; then
        echo "Updating velero to use minio"
        s3Url=$(kubectl -n velero get backupstoragelocation default -ojsonpath='{ .spec.config.s3Url }')
        if [ "$s3Url" = "http://${RGW_HOST}" ]; then
            kubectl -n velero patch backupstoragelocation default --type=merge -p "{\"spec\":{\"config\":{\"s3Url\":\"http://${MINIO_HOST}\",\"publicUrl\":\"http://${MINIO_CLUSTER_IP}\"}}}"

            while read -r resticrepo; do
                oldResticIdentifier=$(kubectl -n velero get resticrepositories "$resticrepo" -ojsonpath="{ .spec.resticIdentifier }")
                newResticIdentifier=$(echo "$oldResticIdentifier" | sed "s/${RGW_HOST}/${MINIO_HOST}/")
                kubectl -n velero patch resticrepositories "$resticrepo" --type=merge -p "{\"spec\":{\"resticIdentifier\":\"${newResticIdentifier}\"}}"
            done < <(kubectl -n velero get resticrepositories --selector=velero.io/storage-location=default --no-headers | awk '{ print $1 }')
        else
            echo "default backupstoragelocation was not rgw, skipping"
        fi
    fi
    if kubernetes_resource_exists velero secret cloud-credentials; then
        if kubectl -n velero get secret cloud-credentials -ojsonpath='{ .data.cloud }' | base64 -d | grep -q "$RGW_ACCESS_KEY_ID"; then
            kubectl -n velero get secret cloud-credentials -ojsonpath='{ .data.cloud }' | base64 -d > cloud
            sed -i "s/aws_access_key_id=.*/aws_access_key_id=${MINIO_ACCESS_KEY_ID}/" cloud
            sed -i "s/aws_secret_access_key=.*/aws_secret_access_key=${MINIO_ACCESS_KEY_SECRET}/" cloud
            cloud=$(cat cloud | base64 -w 0)
            kubectl -n velero patch secret cloud-credentials -p "{\"data\":{\"cloud\":\"${cloud}\"}}"
            rm cloud
        else
            echo "cloud-credentials secret were not for rgw, skipping"
        fi
    fi
    if kubernetes_resource_exists velero daemonset restic; then
        kubectl -n velero rollout restart daemonset restic
    fi
    if kubernetes_resource_exists velero deployment velero; then
        kubectl -n velero rollout restart deployment velero
    fi

    printf "\n${GREEN}Object store migration completed successfully${NC}\n"
}
