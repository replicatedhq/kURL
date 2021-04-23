#!/bin/bash

set -eo pipefail

# shellcheck source=list-all-packages.sh
source ./bin/list-all-packages.sh

function require() {
    if [ -z "$2" ]; then
        echo "validation failed: $1 unset"
        exit 1
    fi
}

require AWS_ACCESS_KEY_ID "${AWS_ACCESS_KEY_ID}"
require AWS_SECRET_ACCESS_KEY "${AWS_SECRET_ACCESS_KEY}"
require S3_BUCKET "${S3_BUCKET}"
require VERSION_TAG "${VERSION_TAG}"

GITSHA="$(git rev-parse HEAD)"

function package_has_changes() {
    local key="$1"
    local path="$2"

    if [ -z "${path}" ]; then
        # if no path then we can't calculate changes
        return 0
    fi

    local upstream_gitsha=
    upstream_gitsha="$(aws s3api head-object --bucket "${S3_BUCKET}" --key "${key}" | grep '"gitsha":' | sed 's/[",:]//g' | awk '{print $2}')"

    if [ -z "${upstream_gitsha}" ]; then
        # if package doesn't exist or have a gitsha it has changes
        return 0
    fi

    if git diff --quiet "${upstream_gitsha}" -- "${path}" "${VERSION_TAG}" -- "${path}" ; then
        return 1
    else
        return 0
    fi
}

function build_and_upload() {
    local package="$1"

    make "dist/${package}"
    MD5="$(openssl md5 -binary "dist/${package}" | base64)"
    aws s3 cp "dist/${package}" "s3://${S3_BUCKET}/dist/${VERSION_TAG}/${package}" \
        --metadata md5="${MD5}",gitsha="${VERSION_TAG}"
    aws s3 cp "s3://${S3_BUCKET}/dist/${VERSION_TAG}/${package}" "s3://${S3_BUCKET}/dist/${package}" \
        --metadata md5="${MD5}",gitsha="${GITSHA}"
    make clean
    if [ -n "$DOCKER_PRUNE" ]; then
        docker system prune --all --force
    fi
}

function copy_package_staging() {
    local package="$1"

    local md5=
    md5="$(aws s3api head-object --bucket "${S3_BUCKET}" --key "staging/${package}" | grep '"md5":' | sed 's/[",:]//g' | awk '{print $2}')"
    aws s3 cp "s3://${S3_BUCKET}/staging/${package}" "s3://${S3_BUCKET}/dist/${VERSION_TAG}/${package}" \
        --metadata md5="${md5}",gitsha="${GITSHA}"
    aws s3 cp "s3://${S3_BUCKET}/staging/${package}" "s3://${S3_BUCKET}/dist/${package}" \
        --metadata md5="${md5}",gitsha="${GITSHA}"
}

function deploy() {
    local package="$1"
    local path="$2"

    # Common must be built rather than copied from staging because the staging common.tar.gz
    # package includes the alpha kurl-util image but the prod common.tar.gz needs a tagged version
    # of the kurl-util image
    if [ "$package" = "common.tar.gz" ] ; then
        echo "s3://${S3_BUCKET}/${package} build and upload"
        build_and_upload "${package}"
        return
    fi

    # The kurl-utils-bin package must be built rather than copied from staging because the staging
    # version is latest and the prod version is tagged.
    if echo "${package}" | grep -q "kurl-bin-utils" ; then
        echo "s3://${S3_BUCKET}/${package} build and upload"
        build_and_upload "${package}"
        return
    fi

    if package_has_changes "dist/${package}" "${path}" ; then
        if package_has_changes "staging/${package}" "${path}" ; then
            echo "s3://${S3_BUCKET}/${package} has changes"
            build_and_upload "${package}"
        else
            echo "s3://${S3_BUCKET}/${package} no changes in staging package"
            copy_package_staging "${package}"
        fi
    else
        echo "s3://${S3_BUCKET}/dist/${package} no changes in package"
    fi
}

function main() {
    git fetch

    # TODO: kubernetes changes do not yet take into account changes in bundles/
    # These need to manually be rebuilt when changing that path.

    while read -r line
    do
        # shellcheck disable=SC2086
        deploy ${line}
    done < <(list_all)
}

main "$@"
