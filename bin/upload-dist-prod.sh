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

for package in $(bin/list-all-packages.sh)
do
    if [ "$package" = "common.tar.gz" ]; then
        # Common must be built rather than copied from staging because the staging common.tar.gz
        # package includes the alpha kurl-util image but the prod common.tar.gz needs a tagged version
        # of the kurl-util image
        make dist/common.tar.gz
        aws s3 cp dist/common.tar.gz s3://$S3_BUCKET/dist/
    elif echo "$package" | grep -q "kurl-util-bin"; then
        # The kurl-utils-bin package must be built rather than copied from staging because the staging
        # version is latest and the prod version is tagged.
        make dist/$package
        aws s3 cp dist/$package s3://$S3_BUCKET/dist/
    else
        # All other packages are copied directly from staging/ to dist/
        aws s3 cp s3://$S3_BUCKET/staging/$package s3://$S3_BUCKET/dist/$package
    fi
done
