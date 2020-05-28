
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
    local bucket=$1
    local acl="x-amz-acl:private"
    local d=$(date +"%a, %d %b %Y %T %z")
    local string="PUT\n\n\n${d}\n${acl}\n/$bucket"
    local sig=$(echo -en "${string}" | openssl sha1 -hmac "${OBJECT_STORE_SECRET_KEY}" -binary | base64)

    curl -X PUT  \
        --noproxy "*" \
        -H "Host: $OBJECT_STORE_CLUSTER_IP" \
        -H "Date: $d" \
        -H "$acl" \
        -H "Authorization: AWS $OBJECT_STORE_ACCESS_KEY:$sig" \
        "http://$OBJECT_STORE_CLUSTER_IP/$bucket" >/dev/null
}
