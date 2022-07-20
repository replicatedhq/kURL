#!/bin/bash

set -euo pipefail

ADDON_VERSION=

VERSION=
function get_latest_version() {
    VERSION=$(curl -s https://api.github.com/repos/weaveworks/weave/releases/latest | \
        grep '"name":' | \
        grep -Eo "[0-9]+\.[0-9]+\.[0-9]+" | \
        head -1)
}

IMAGE_PATCH_VERSION=
function get_images_patch_version() {
    IMAGE_PATCH_VERSION=$(docker run quay.io/skopeo/stable --override-os linux \
        list-tags "docker://kurlsh/weave-kube" | \
        jq -r '.Tags | .[]' | \
        grep "${VERSION}" | \
        grep -E "\-2[0-9]{7}-")
}

function add_as_latest() {
    sed -i "/cron-weave-update/a\    \"${ADDON_VERSION}\"\," ../../../web/src/installers/versions.js
}

function generate() {
    local dir="../${ADDON_VERSION}"

    mkdir -p "$dir"

    cp -r base/* "$dir/"
    sed -i "s/__WEAVE_VERSION__/$VERSION/g" "$dir/Manifest"
    sed -i "s/__WEAVE_VERSION__/$VERSION/g" "$dir/patch-daemonset.yaml"

    curl -L --fail "https://github.com/weaveworks/weave/releases/download/v$VERSION/weave-daemonset-k8s-1.11.yaml" \
        > "$dir/weave-daemonset-k8s-1.11.yaml"

    if [ -n "$IMAGE_PATCH_VERSION" ]; then
        sed -i "s/weaveworks\/\(weave[^:]*\):$VERSION/kurlsh\/\1:${IMAGE_PATCH_VERSION}/" "$dir/Manifest"
        sed -i "s/weaveworks\/\(weave[^:]*\):$VERSION/kurlsh\/\1:${IMAGE_PATCH_VERSION}/" "$dir/weave-daemonset-k8s-1.11.yaml"
        sed -i "s/weaveworks\/\(weave[^:]*\):$VERSION/kurlsh\/\1:${IMAGE_PATCH_VERSION}/" "$dir/patch-daemonset.yaml"
    fi
}

function main() {
    VERSION=${1-}
    if [ -z "$VERSION" ]; then
        get_latest_version
    fi
    ADDON_VERSION="$VERSION"

    get_images_patch_version

    if [ -n "$IMAGE_PATCH_VERSION" ]; then
        ADDON_VERSION="$(echo "$IMAGE_PATCH_VERSION" | sed -e 's/-[0-9a-f]\{7\}$//')"
    fi

    if [ -d "../$ADDON_VERSION" ]; then
        echo "Weave ${ADDON_VERSION} add-on already exists"
        exit 0
    fi

    generate

    add_as_latest

    echo "::set-output name=weave::$ADDON_VERSION"
}

main "$@"
