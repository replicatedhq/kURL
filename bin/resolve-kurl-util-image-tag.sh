#!/bin/bash

# resolve_kurl_util_image_tag <build_util_image> <version_tag>
#
# Returns the replicated/kurl-util tag a built installer must reference for
# this run. The tag is always the per-version tag -- never :alpha -- because
# that is the only tag the generated installer/kurlnet manifests end up
# pinned to (see deploy-staging.yaml, which always retags+pushes :alpha under
# the release's VERSION_TAG even when it doesn't rebuild the image). What
# build_util_image controls is only how that tag's image gets produced: a
# fresh build (true) or a cheap retag+push of the already-built :alpha image
# (false, the default fast path).
function resolve_kurl_util_image_tag() {
    # shellcheck disable=SC2034 # kept for the caller-facing signature/contract; the tag itself never varies on it
    local build_util_image="$1"
    local version_tag="$2"

    if [ -z "${version_tag}" ]; then
        echo "resolve_kurl_util_image_tag: version_tag is required" >&2
        return 1
    fi

    echo "replicated/kurl-util:${version_tag}"
}
