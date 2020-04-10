#!/bin/bash

# Generate and export the kurl util image reference.

set -eo pipefail

function image_export() {
    local prev_setu="${-//[^u]/}"

    set +u

    local tag=alpha
    # TODO remove once off circle
    if [ -n "$CIRCLE_TAG" ]; then
        tag="$CIRCLE_TAG"
    elif [ "$CIRCLE_BRANCH" = "beta" ]; then
        tag="beta"
    fi

    if echo "$GITHUB_REF" | grep '^refs/tags'; then
        tag=$(echo $GITHUB_REF | awk -F'/' '{ print $NF }')
    elif [ "$GITHUB_REF" = "refs/heads/beta" ]; then
        tag="beta"
    fi

    export KURL_UTIL_IMAGE=replicated/kurl-util:$tag

    if [ -n "$prev_setu" ]; then set -u; fi
}

image_export
