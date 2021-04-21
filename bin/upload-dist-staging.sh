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

GITSHA="$(git rev-parse HEAD)"

function upload() {
    local package="$1"

    make "dist/${package}"
    MD5="$(openssl md5 -binary "dist/${package}" | base64)"
    aws s3 cp "dist/${package}" "s3://${S3_BUCKET}/staging/${GITSHA}/$PKG" \
        --metadata md5="${MD5}",gitsha="${GITSHA}"
    aws s3 cp "s3://${S3_BUCKET}/staging/${GITSHA}/${package}" "s3://${S3_BUCKET}/staging/$PKG"
    make clean
    if [ -n "$DOCKER_PRUNE" ]; then
        docker system prune --all --force
    fi
}

# always upload small packages that change often
upload common.tar.gz
upload kurl-bin-utils-latest.tar.gz

for package in $(bin/list-all-packages.sh)
do
    if ! aws s3api head-object --bucket="${S3_BUCKET}" --key="staging/${GITSHA}/${package}" &>/dev/null; then
        upload "${package}"
    else
        echo "s3://${S3_BUCKET}/staging/${GITSHA}/${package} already exists"
        aws s3 cp "s3://${S3_BUCKET}/staging/${GITSHA}/${package}" "s3://${S3_BUCKET}/staging/$PKG"
    fi
done
