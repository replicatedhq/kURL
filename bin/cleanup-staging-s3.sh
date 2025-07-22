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

echo "cleaning up old staging releases"
# get the objects inside versioned staging buckets
# then filter it for objects with timestamps older than 31 days
# and then delete those objects older than 31 days
objects=$(aws s3api list-objects --bucket "$S3_BUCKET" --prefix 'staging/v20' --query 'Contents[].{Key: Key, LastModified: LastModified}' --output json)
if [ "$objects" != "null" ]; then
    echo "Found staging objects: $objects"
    echo "$objects" | jq "map(select(.LastModified | .[0:19] + \"Z\" | fromdateiso8601 < $monthAgo)) | .[].Key" | \
        xargs -I {} aws s3api delete-object --bucket "$S3_BUCKET" --key "{}"
fi

echo "cleaning up old PR files"
# get the objects inside the PR folder
# then filter it for objects with timestamps older than 31 days
# and then delete those objects older than 31 days
objects=$(aws s3api list-objects --bucket "$S3_BUCKET" --prefix 'pr/' --query 'Contents[].{Key: Key, LastModified: LastModified}' --output json)
if [ "$objects" != "null" ]; then
    echo "Found PR objects: $objects"
    echo "$objects" | jq "map(select(.LastModified | .[0:19] + \"Z\" | fromdateiso8601 < $monthAgo)) | .[].Key" | { grep -v '"pr/"' || test $? = 1; } | \
        xargs -I {} aws s3api delete-object --bucket "$S3_BUCKET" --key "{}"
fi
