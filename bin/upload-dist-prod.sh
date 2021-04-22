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

function upload_staging() {
    local package="$1"

    make "dist/${package}"
    MD5="$(openssl md5 -binary "dist/${package}" | base64)"
    aws s3 cp "dist/${package}" "s3://${S3_BUCKET}/staging/${GITSHA}/$PKG" \
        --metadata md5="${MD5}",gitsha="${GITSHA}"
    make clean
    if [ -n "$DOCKER_PRUNE" ]; then
        docker system prune --all --force
    fi
}

# build and upload missing staging packages
for package in $(bin/list-all-packages.sh)
do
    if ! aws s3api head-object --bucket="${S3_BUCKET}" --key="staging/${GITSHA}/${package}" &>/dev/null; then
        upload_staging "${package}"
    else
        echo "s3://${S3_BUCKET}/staging/${GITSHA}/${package} already exists"
    fi
done

for package in $(bin/list-all-packages.sh)
do
    if [ "$package" = "common.tar.gz" ] || echo "${package}" | grep -q "kurl-bin-utils" ; then
        # Common must be built rather than copied from staging because the staging common.tar.gz
        # package includes the alpha kurl-util image but the prod common.tar.gz needs a tagged version
        # of the kurl-util image

        # The kurl-utils-bin package must be built rather than copied from staging because the staging
        # version is latest and the prod version is tagged.

        make "dist/${package}"
        MD5="$(openssl md5 -binary "dist/${package}" | base64)"
        aws s3 cp "dist/${package}" "s3://${S3_BUCKET}/dist/${GITSHA}/${package}" \
            --metadata md5="${MD5}",gitsha="${GITSHA}"
        aws s3 cp "s3://${S3_BUCKET}/dist/${GITSHA}/${package}" "s3://${S3_BUCKET}/dist/${package}"
    else
        # copy staging package to prod
        aws s3 cp "s3://${S3_BUCKET}/staging/${GITSHA}/${package}" "s3://${S3_BUCKET}/dist/${GITSHA}/${package}"
        aws s3 cp "s3://${S3_BUCKET}/staging/${GITSHA}/${package}" "s3://${S3_BUCKET}/dist/${package}"
    fi
done
