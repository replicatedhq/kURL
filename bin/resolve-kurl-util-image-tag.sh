#!/bin/bash

# resolve_kurl_util_image_tag <version_tag>
#
# Returns the replicated/kurl-util tag a built installer must reference for
# this run. The tag is always the per-version tag -- never :alpha -- because
# that is the only tag the generated installer/kurlnet manifests end up
# pinned to (see deploy-staging.yaml, which always retags+pushes :alpha under
# the release's VERSION_TAG even when it doesn't rebuild the image).
function resolve_kurl_util_image_tag() {
    local version_tag="$1"

    if [ -z "${version_tag}" ]; then
        echo "resolve_kurl_util_image_tag: version_tag is required" >&2
        return 1
    fi

    echo "replicated/kurl-util:${version_tag}"
}
