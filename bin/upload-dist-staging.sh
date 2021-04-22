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

GITSHA="$(git rev-parse HEAD)"

function package_has_changes() {
    local type="$1"
    local package="$2"
    local name="$3"
    local version="$4"

    local upstream_gitsha=
    upstream_gitsha="$(aws s3api head-object --bucket "${S3_BUCKET}" --key "staging/${package}" | grep '"gitsha":' | sed 's/[",:]//g' | awk '{print $2}')"

    if [ -z "${upstream_gitsha}" ]; then
        # if package doesn't exist or have a gitsha it has changes
        return 0
    fi

    if git diff --quiet "${upstream_gitsha}" -- "${type}/${name}/${version}/" "${GITSHA}" -- "${type}/${name}/${version}/" ; then
        return 1
    else
        return 0
    fi
}

function upload() {
    local package="$1"

    make "dist/${package}"
    MD5="$(openssl md5 -binary "dist/${package}" | base64)"
    aws s3 cp "dist/${package}" "s3://${S3_BUCKET}/staging/${GITSHA}/$PKG" \
        --metadata md5="${MD5}",gitsha="${GITSHA}"
    aws s3 cp "s3://${S3_BUCKET}/staging/${GITSHA}/${package}" "s3://${S3_BUCKET}/staging/$PKG" \
        --metadata md5="${MD5}",gitsha="${GITSHA}"
    make clean
    if [ -n "$DOCKER_PRUNE" ]; then
        docker system prune --all --force
    fi
}

function deploy_package() {
    local type="$1"
    local package="$2"
    local name="$3"
    local version="$4"

    if ! aws s3api head-object --bucket="${S3_BUCKET}" --key="staging/${GITSHA}/${package}" &>/dev/null; then
        if package_has_changes "${type}" "${package}" "${name}" "${version}" ; then
            echo "s3://${S3_BUCKET}/staging/${package} has changes"
            upload "${package}"
        else
            echo "s3://${S3_BUCKET}/staging/${package} no changes in package"
            local md5=
            md5="$(aws s3api head-object --bucket "${S3_BUCKET}" --key "staging/${package}" | grep '"md5":' | sed 's/[",:]//g' | awk '{print $2}')"
            aws s3 cp "s3://${S3_BUCKET}/staging/${package}" "s3://${S3_BUCKET}/staging/${GITSHA}/$PKG" \
                --metadata md5="${md5}",gitsha="${GITSHA}"
        fi
    else
        echo "s3://${S3_BUCKET}/staging/${GITSHA}/${package} already exists"
        local md5=
        md5="$(aws s3api head-object --bucket "${S3_BUCKET}" --key "staging/${GITSHA}/${package}" | grep '"md5":' | sed 's/[",:]//g' | awk '{print $2}')"
        aws s3 cp "s3://${S3_BUCKET}/staging/${GITSHA}/${package}" "s3://${S3_BUCKET}/staging/$PKG" \
            --metadata md5="${md5}",gitsha="${GITSHA}"
    fi
}

function deploy_other() {
    local package="$2"

    if ! aws s3api head-object --bucket="${S3_BUCKET}" --key="staging/${GITSHA}/${package}" &>/dev/null; then
        echo "s3://${S3_BUCKET}/staging/${GITSHA}/${package} upload"
        upload "${package}"
    else
        echo "s3://${S3_BUCKET}/staging/${GITSHA}/${package} already exists"
        local md5=
        md5="$(aws s3api head-object --bucket "${S3_BUCKET}" --key "staging/${GITSHA}/${package}" | grep '"md5":' | sed 's/[",:]//g' | awk '{print $2}')"
        aws s3 cp "s3://${S3_BUCKET}/staging/${GITSHA}/${package}" "s3://${S3_BUCKET}/staging/$PKG" \
            --metadata md5="${md5}",gitsha="${GITSHA}"
    fi
}

function main() {
    git fetch

    # always upload small packages that change often
    upload common.tar.gz
    upload kurl-bin-utils-latest.tar.gz

    while read -r line
    do
        # shellcheck disable=SC2086
        deploy_package "addon" ${line}
    done < <(list_all_addons)

    while read -r line
    do
        # shellcheck disable=SC2086
        deploy_package "package" ${line}
    done < <(list_all_packages)

    while read -r line
    do
        # shellcheck disable=SC2086
        deploy_other "other" ${line}
    done < <(list_other)
}

main "$@"
