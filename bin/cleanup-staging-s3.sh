#!/bin/bash
set -eo pipefail

function require() {
    if [ -z "$2" ]; then
        echo "validation failed: $1 unset"
        exit 1
    fi
}

require AWS_ACCESS_KEY_ID "${AWS_ACCESS_KEY_ID}"
require AWS_SECRET_ACCESS_KEY "${AWS_SECRET_ACCESS_KEY}"
require AWS_REGION "${AWS_REGION}"
require S3_BUCKET "${S3_BUCKET}"

monthAgo=$(date --date "-744 hour" "+%s")

function delete_objects_batch() {
    local bucket="$1"
    local keys_json="$2"

    if [ -z "$keys_json" ] || [ "$keys_json" = "[]" ]; then
        return 0
    fi

    local delete_json
    delete_json=$(echo "$keys_json" | jq '{Objects: map({Key: .})}')

    local result
    result=$(aws s3api delete-objects \
        --bucket "$bucket" \
        --delete "$delete_json")

    # Log any errors from partial failures
    local errors
    errors=$(echo "$result" | jq -c '.Errors // empty')
    if [ -n "$errors" ]; then
        echo "WARNING: delete-objects reported errors:"
        echo "$errors"
    fi
}

function list_all_objects() {
    local bucket="$1"
    local prefix="$2"

    local all_objects="[]"
    local continuation_token=""

    while true; do
        local response
        if [ -n "$continuation_token" ]; then
            response=$(aws s3api list-objects-v2 \
                --bucket "$bucket" \
                --prefix "$prefix" \
                --continuation-token "$continuation_token" \
                --query '{Contents: Contents[].{Key: Key, LastModified: LastModified}, IsTruncated: IsTruncated, NextContinuationToken: NextContinuationToken}' \
                --output json)
        else
            response=$(aws s3api list-objects-v2 \
                --bucket "$bucket" \
                --prefix "$prefix" \
                --query '{Contents: Contents[].{Key: Key, LastModified: LastModified}, IsTruncated: IsTruncated, NextContinuationToken: NextContinuationToken}' \
                --output json)
        fi

        local objects
        objects=$(echo "$response" | jq '.Contents // []')
        all_objects=$(echo "$all_objects $objects" | jq -s 'add')

        local is_truncated
        is_truncated=$(echo "$response" | jq -r '.IsTruncated // false')

        if [ "$is_truncated" != "true" ]; then
            break
        fi

        continuation_token=$(echo "$response" | jq -r '.NextContinuationToken // empty')

        if [ -z "$continuation_token" ]; then
            echo "WARNING: list-objects-v2 returned IsTruncated=true but no NextContinuationToken"
            break
        fi
    done

    echo "$all_objects"
}

function cleanup_prefix() {
    local prefix="$1"

    echo "cleaning up old objects for prefix '$prefix'"

    local objects
    objects=$(list_all_objects "$S3_BUCKET" "$prefix")

    if [ "$objects" = "null" ] || [ -z "$objects" ] || [ "$objects" = "[]" ]; then
        echo "no objects found for prefix $prefix"
        return 0
    fi

    local count_all
    count_all=$(echo "$objects" | jq 'length')
    echo "found $count_all total objects for prefix $prefix"

    local keys_to_delete
    keys_to_delete=$(echo "$objects" | jq -r --arg prefix "$prefix" '
        map(select(.LastModified | .[0:19] + "Z" | fromdateiso8601 < '"$monthAgo"'))
        | map(.Key)
        | map(select(. != $prefix))
    ')

    if [ "$keys_to_delete" = "[]" ] || [ -z "$keys_to_delete" ]; then
        echo "no old objects to delete for prefix $prefix"
        return 0
    fi

    local count
    count=$(echo "$keys_to_delete" | jq 'length')
    echo "found $count objects to delete for prefix $prefix"

    echo "$keys_to_delete" | \
        jq -c '. as $a | [range(0; length; 1000) | $a[.:.+1000]] | .[]' | \
        while read -r batch; do
            delete_objects_batch "$S3_BUCKET" "$batch" || exit 1
        done

    echo "finished deleting old objects for prefix '$prefix'"
}

echo "cleaning up old staging releases"
cleanup_prefix "staging/v20"

echo "cleaning up old PR files"
cleanup_prefix "pr/"
