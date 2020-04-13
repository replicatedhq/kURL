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
require S3_BUCKET "${S3_BUCKET}"

function upload() {
    local package="$1"

    make dist/$package
    aws s3 cp dist/$package s3://$S3_BUCKET/staging/
    make clean
    if [ -n "$DOCKER_PRUNE" ]; then
        docker system prune --all --force
    fi
}

# always build the common package
upload common.tar.gz

for package in $(bin/list-all-packages.sh)
do
    if [ -n "$REPLACE_PACKAGES" ] || ! aws s3api head-object --bucket=$S3_BUCKET --key=staging/$package &>/dev/null; then
        upload $package
    else
        echo "s3://$S3_BUCKET/staging/$package already exists"
    fi
done
