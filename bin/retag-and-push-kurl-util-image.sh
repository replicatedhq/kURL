#!/bin/bash

# retry <retries> <command...>
#
# Exponential-backoff retry for flaky network calls (mirrors the S3 retry
# helpers inlined in testgrid-pr.yaml).
function retry() {
    local retries="$1"; shift
    local count=0 exit wait
    until "$@"; do
        exit=$?
        wait=$((2 ** count))
        count=$((count + 1))
        if [ "${count}" -lt "${retries}" ]; then
            echo "Retry ${count}/${retries} exited ${exit}, retrying in ${wait}s..." >&2
            sleep "${wait}"
        else
            echo "Retry ${count}/${retries} exited ${exit}, no more retries left." >&2
            return "${exit}"
        fi
    done
    return 0
}

# retag_and_push_kurl_util_image <source_image> <dest_image>
#
# Retags an already-built kurl-util image under a new tag and pushes it,
# retrying the pull and push against transient DockerHub failures. Used by
# testgrid-pr.yaml's cheap default path (build-kurl-util-image=false) to
# publish the per-version RC tag that the generated installer/kurlnet
# manifests are pinned to, without a full rebuild (replicatedhq/kURL#6171
# bug 2).
function retag_and_push_kurl_util_image() {
    local source_image="$1"
    local dest_image="$2"

    if [ -z "${source_image}" ] || [ -z "${dest_image}" ]; then
        echo "retag_and_push_kurl_util_image: source_image and dest_image are required" >&2
        return 1
    fi

    retry 5 docker pull "${source_image}" \
        && docker tag "${source_image}" "${dest_image}" \
        && retry 5 docker push "${dest_image}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    retag_and_push_kurl_util_image "$@"
fi
