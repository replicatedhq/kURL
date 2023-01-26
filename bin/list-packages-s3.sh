#!/bin/bash

# List packages for a particular staging release from s3
# Inovked by ./bin/list-all-packages-actions-matrix.sh

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
require STAGING_RELEASE "${STAGING_RELEASE}"

STAGING_PREFIX="${STAGING_PREFIX:-staging}"

# Get list of packages associated with a staging release from s3:
# Exclude common and kurl-bin-utils packages => grep -vE "/common.*" | grep -vE "/kurl-bin-utils-*"
# Get raw strings NOT JSON encoded strings => jq -rc '.[]'
# Exclude directories => grep -vE "^${STAGING_PREFIX}/${STAGING_RELEASE}/$"
# Output the file name stripping the directory prefix => awk '{print $NF}' FS=/
list_s3_packages=$(aws s3api list-objects-v2 --bucket "${S3_BUCKET}" --prefix "${STAGING_PREFIX}/${STAGING_RELEASE}" --query 'Contents[].Key' | jq -rc '.[]' | grep -vE "^${STAGING_PREFIX}/${STAGING_RELEASE}/$" | grep -vE "/common.*" | grep -vE "/kurl-bin-utils-*" | awk '{print $NF}' FS=/)

echo "${list_s3_packages}"
