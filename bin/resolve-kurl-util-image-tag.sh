#!/bin/bash

# resolve_kurl_util_image_tag <version_tag>
#
# Returns the replicated/kurl-util tag a built installer must reference for
# this run. The tag is always the per-version tag -- never :alpha -- because
# kurl.sh renders the generated installer/kurlnet manifests server-side using
# the same convention every real release relies on: it fills KURL_UTIL_IMAGE
# with replicated/kurl-util:<installerVersion>, the exact per-version tag
# deploy-staging.yaml's kurl-util-image job always pushes (build :alpha,
# `docker tag` it to the release's VERSION_TAG, push both). There is no
# server-side way to tell it to use :alpha for one specific version instead,
# so switching the installer to reference :alpha directly is not an option.
function resolve_kurl_util_image_tag() {
    local version_tag="$1"

    if [ -z "${version_tag}" ]; then
        echo "resolve_kurl_util_image_tag: version_tag is required" >&2
        return 1
    fi

    echo "replicated/kurl-util:${version_tag}"
}
