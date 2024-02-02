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
require AWS_REGION "${AWS_REGION}"
require S3_BUCKET "${S3_BUCKET}"

GITSHA="$(git rev-parse HEAD)"

function package_has_changes() {
    local key="$1"
    local path="$2"

    if [ -z "${path}" ]; then
        # if no path then we can't calculate changes
        echo "Path empty for package ${package}"
        return 0
    fi

    if is_old_kubernetes "${key}" ; then
        # we cannot rebuild old kubernetes packages, so we should always say there were no changes
        echo "Old kubernetes package ${package}"
        return 1
    fi

    local upstream_gitsha=
    upstream_gitsha="$(aws s3api head-object --bucket "${S3_BUCKET}" --key "${key}" | grep '"gitsha":' | sed 's/[",:]//g' | awk '{print $2}')"

    if [ -z "${upstream_gitsha}" ]; then
        # if package doesn't exist or have a gitsha it has changes
        echo "Upstream gitsha empty for package ${package}"
        return 0
    fi

    if ( set -x; git diff --quiet "${upstream_gitsha}" -- "${path}" "${GITSHA}" -- "${path}" ) ; then
        return 1
    else
        return 0
    fi
}

# kubernetes packages before 1.24 are not available in the new yum/apt repo, and so should be copied
function is_old_kubernetes() {
    local package="$1"
    if echo "${package}" | grep -q "kubernetes-1.15" ; then
        return 0
    fi
    if echo "${package}" | grep -q "kubernetes-1.16" ; then
        return 0
    fi
    if echo "${package}" | grep -q "kubernetes-1.17" ; then
        return 0
    fi
    if echo "${package}" | grep -q "kubernetes-1.18" ; then
        return 0
    fi
    if echo "${package}" | grep -q "kubernetes-1.19" ; then
        return 0
    fi
    if echo "${package}" | grep -q "kubernetes-1.20" ; then
        return 0
    fi
    if echo "${package}" | grep -q "kubernetes-1.21" ; then
        return 0
    fi
    if echo "${package}" | grep -q "kubernetes-1.22" ; then
        return 0
    fi
    if echo "${package}" | grep -q "kubernetes-1.23" ; then
        return 0
    fi
    return 1
}

function build_and_upload() {
    local package="$1"

    echo "building package ${package}"
    make "dist/${package}"
    MD5="$(openssl md5 -binary "dist/${package}" | base64)"

    echo "uploading package ${package} to ${S3_BUCKET} with metadata md5=\"${MD5}\",gitsha=\"${GITSHA}\""
    retry 5 aws s3 cp "dist/${package}" "s3://${S3_BUCKET}/staging/${package}" \
        --metadata-directive REPLACE --metadata md5="${MD5}",gitsha="${GITSHA}"

    echo "cleaning up after uploading ${package}"
    make clean
    if [ -n "$DOCKER_PRUNE" ]; then
        docker system prune --all --force
    fi
}

function deploy() {
    local package="$1"
    local path="$2"

    # always upload small packages that change often
    if [ "$package" = "install.tmpl" ] \
        || [ "$package" = "join.tmpl" ] \
        || [ "$package" = "upgrade.tmpl" ] \
        || [ "$package" = "tasks.tmpl" ] \
        || [ "$package" = "common.tar.gz" ] \
        || echo "${package}" | grep -q "kurl-bin-utils" ; then

        echo "s3://${S3_BUCKET}/staging/${package} build and upload"
        build_and_upload "${package}"
        return
    fi

    if package_has_changes "staging/${package}" "${path}" ; then
        echo "s3://${S3_BUCKET}/staging/${package} has changes"
        build_and_upload "${package}"
    else
        echo "s3://${S3_BUCKET}/staging/${package} no changes in package"
    fi
}

function retry {
    local retries=$1
    shift

    local count=0
    until "$@"; do
        exit=$?
        wait=$((2 ** $count))
        count=$(($count + 1))
        if [ $count -lt $retries ]; then
            echo "Retry $count/$retries exited $exit, retrying in $wait seconds..."
            sleep $wait
        else
            echo "Retry $count/$retries exited $exit, no more retries left."
            return $exit
        fi
    done
    return 0
}

function main() {
    local batch="$1"
    echo "Uploading ${batch} packages to s3://${S3_BUCKET}/staging/"

    git fetch

    # TODO: kubernetes changes do not yet take into account changes in bundles/
    # These need to manually be rebuilt when changing that path.

    while read -r line; do
        package="$(echo "${line}" | cut -f1 -d' ')"

        for pkg in ${batch}; do
            if [ -n "${pkg}" ] && [ "${pkg}" = "${package}" ]; then
                path="$(echo "${line}" | cut -f2 -d' ')"

                deploy "${package}" "${path}"
                break
            fi
        done
    done < <(list_all)
}

main "$@"
