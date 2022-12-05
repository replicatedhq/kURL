#!/bin/bash
set -eo pipefail

require AWS_ACCESS_KEY_ID "${AWS_ACCESS_KEY_ID}"
require AWS_SECRET_ACCESS_KEY "${AWS_SECRET_ACCESS_KEY}"
require AWS_REGION "${AWS_REGION}"
require S3_BUCKET "${S3_BUCKET}"

monthAgo=$(date -v-744H '+%s')

# get the objects inside versioned staging buckets
# then filter it for objects with timestamps older than 31 days
# and then delete those objects older than 31 days
aws s3api list-objects --bucket "$S3_BUCKET" --prefix 'staging/v20' --query 'Contents[].{Key: Key, LastModified: LastModified}' | \
    jq "map(select(.LastModified | .[0:19] + \"Z\" | fromdateiso8601 < $monthAgo)) | .[].Key" | \
    xargs -I {} echo "{}"
#    xargs -I {} aws s3api delete-object --bucket "$S3_BUCKET" --key "{}"
