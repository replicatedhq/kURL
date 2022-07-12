
# object store functions (create bucket, write object, get object)
function object_store_bucket_exists() {
    local bucket=$1
    local acl="x-amz-acl:private"
    local d=$(LC_TIME="en_US.UTF-8" TZ="UTC" date +"%a, %d %b %Y %T %z")
    local string="HEAD\n\n\n${d}\n${acl}\n/$bucket"
    local sig=$(echo -en "${string}" | openssl sha1 -hmac "${OBJECT_STORE_SECRET_KEY}" -binary | base64)

    curl -fsSL -I \
        --globoff \
        --noproxy "*" \
        -H "Host: $OBJECT_STORE_CLUSTER_IP" \
        -H "Date: $d" \
        -H "$acl" \
        -H "Authorization: AWS $OBJECT_STORE_ACCESS_KEY:$sig" \
        "http://$OBJECT_STORE_CLUSTER_IP/$bucket"
}

function _object_store_create_bucket() {
  local bucket=$1
  local acl="x-amz-acl:private"
  local d=$(LC_TIME="en_US.UTF-8" TZ="UTC" date +"%a, %d %b %Y %T %z")
  local string="PUT\n\n\n${d}\n${acl}\n/$bucket"
  local sig=$(echo -en "${string}" | openssl sha1 -hmac "${OBJECT_STORE_SECRET_KEY}" -binary | base64)
  curl -fsSL -X PUT  \
    --globoff \
    --noproxy "*" \
    -H "Host: $OBJECT_STORE_CLUSTER_IP" \
    -H "Date: $d" \
    -H "$acl" \
    -H "Authorization: AWS $OBJECT_STORE_ACCESS_KEY:$sig" \
    "http://$OBJECT_STORE_CLUSTER_IP/$bucket"
}

function object_store_create_bucket() {
    if object_store_bucket_exists "$1" ; then
        return 0
    fi
    if ! _object_store_create_bucket "$1" ; then
        echo "failed to create bucket $1"
        return 1
    fi
    echo "object store bucket $1 created"
}

function object_store_write_object() {
  local bucket=$1
  local file=$2
  local resource="/${bucket}/${file}"
  local contentType="application/x-compressed-tar"
  local d=$(LC_TIME="en_US.UTF-8" TZ="UTC" date +"%a, %d %b %Y %T %z")
  local string="PUT\n\n${contentType}\n${d}\n${resource}"
  local sig=$(echo -en "${string}" | openssl sha1 -hmac "${OBJECT_STORE_SECRET_KEY}" -binary | base64)

  curl -X PUT -T "${file}" \
    --globoff \
    --noproxy "*" \
    -H "Host: $OBJECT_STORE_CLUSTER_IP" \
    -H "Date: $d" \
    -H "Content-Type: ${contentType}" \
    -H "Authorization: AWS $OBJECT_STORE_ACCESS_KEY:$sig" \
    "http://$OBJECT_STORE_CLUSTER_IP$resource"
}

function object_store_get_object() {
  local bucket=$1
  local file=$2
  local resource="/${bucket}/${file}"
  local contentType="application/x-compressed-tar"
  local d=$(LC_TIME="en_US.UTF-8" TZ="UTC" date +"%a, %d %b %Y %T %z")
  local string="GET\n\n${contentType}\n${d}\n${resource}"
  local sig=$(echo -en "${string}" | openssl sha1 -hmac "${OBJECT_STORE_SECRET_KEY}" -binary | base64)

  curl -X GET -o "${file}" \
  --globoff \
  --noproxy "*" \
  -H "Host: $OBJECT_STORE_CLUSTER_IP" \
  -H "Date: $d" \
  -H "Content-Type: ${contentType}" \
  -H "Authorization: AWS $OBJECT_STORE_ACCESS_KEY:$sig" \
  "http://$OBJECT_STORE_CLUSTER_IP$resource"
}

function rook_ecph_object_store_info() {
    export OBJECT_STORE_ACCESS_KEY=$(kubectl -n rook-ceph get secret rook-ceph-object-user-rook-ceph-store-kurl -o yaml | grep AccessKey | head -1 | awk '{print $2}' | base64 --decode)
    export OBJECT_STORE_SECRET_KEY=$(kubectl -n rook-ceph get secret rook-ceph-object-user-rook-ceph-store-kurl -o yaml | grep SecretKey | head -1 | awk '{print $2}' | base64 --decode)
    export OBJECT_STORE_CLUSTER_IP=$(kubectl -n rook-ceph get service rook-ceph-rgw-rook-ceph-store | tail -n1 | awk '{ print $3}')
}

function minio_object_store_info() {
    export OBJECT_STORE_ACCESS_KEY=$(kubectl -n minio get secret minio-credentials -ojsonpath='{ .data.MINIO_ACCESS_KEY }' | base64 --decode)
    export OBJECT_STORE_SECRET_KEY=$(kubectl -n minio get secret minio-credentials -ojsonpath='{ .data.MINIO_SECRET_KEY }' | base64 --decode)
    export OBJECT_STORE_CLUSTER_IP=$(kubectl -n minio get service minio | tail -n1 | awk '{ print $3}')
}
