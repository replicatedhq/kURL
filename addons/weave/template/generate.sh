#!/bin/bash

set -euo pipefail

VERSION=
ADDON_VERSION=
WEAVE_KUBE_IMAGE_PATCH_VERSION=
WEAVE_NPC_IMAGE_PATCH_VERSION=
WEAVE_EXEC_IMAGE_PATCH_VERSION=

function get_latest_version() {
    VERSION=$(curl -s https://api.github.com/repos/weaveworks/weave/releases/latest | \
        grep '"name":' | \
        grep -Eo "[0-9]+\.[0-9]+\.[0-9]+" | \
        head -1)
}

function get_images_patch_version() {
    local image="$1"
    docker run quay.io/skopeo/stable --override-os linux \
        list-tags "docker://${image}" | \
        jq -r '.Tags | .[]' | \
        grep "${VERSION}" | \
        grep -E "\-2[0-9]{7}-"
}

function get_addon_version() {
    local versions="$@"
    # sort in reverse to get the newest version and strip off the git sha suffix
    echo $versions | xargs -n1 | sort -r | xargs \
        | awk '{print $1}' \
        | sed -e 's/-[0-9a-f]\{7\}$//'
}

function add_as_latest() {
    if ! sed '0,/cron-weave-update/d' ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -q "${ADDON_VERSION}" ; then
        sed -i "/cron-weave-update/a\    \"${ADDON_VERSION}\"\," ../../../web/src/installers/versions.js
    fi
}

function generate() {
    local dir="../${ADDON_VERSION}"

    mkdir -p "$dir"

    cp -r base/* "$dir/"
    sed -i "s/__WEAVE_VERSION__/$VERSION/g" "$dir/Manifest"
    sed -i "s/__WEAVE_VERSION__/$VERSION/g" "$dir/patch-daemonset.yaml"

    curl -L --fail "https://github.com/weaveworks/weave/releases/download/v$VERSION/weave-daemonset-k8s-1.11.yaml" \
        > "$dir/weave-daemonset-k8s-1.11.yaml"

    if [ -n "$WEAVE_KUBE_IMAGE_PATCH_VERSION" ]; then
        sed -i "s/weaveworks\/weave-kube:$VERSION/kurlsh\/weave-kube:${WEAVE_KUBE_IMAGE_PATCH_VERSION}/" "$dir/Manifest"
        sed -i "s/weaveworks\/weave-kube:$VERSION/kurlsh\/weave-kube:${WEAVE_KUBE_IMAGE_PATCH_VERSION}/" "$dir/weave-daemonset-k8s-1.11.yaml"
    fi

    if [ -n "$WEAVE_NPC_IMAGE_PATCH_VERSION" ]; then
        sed -i "s/weaveworks\/weave-npc:$VERSION/kurlsh\/weave-npc:${WEAVE_NPC_IMAGE_PATCH_VERSION}/" "$dir/Manifest"
        sed -i "s/weaveworks\/weave-npc:$VERSION/kurlsh\/weave-npc:${WEAVE_NPC_IMAGE_PATCH_VERSION}/" "$dir/weave-daemonset-k8s-1.11.yaml"
    fi

    if [ -n "$WEAVE_EXEC_IMAGE_PATCH_VERSION" ]; then
        sed -i "s/weaveworks\/weaveexec:$VERSION/kurlsh\/weaveexec:${WEAVE_EXEC_IMAGE_PATCH_VERSION}/" "$dir/Manifest"
        sed -i "s/weaveworks\/weaveexec:$VERSION/kurlsh\/weaveexec:${WEAVE_EXEC_IMAGE_PATCH_VERSION}/" "$dir/patch-daemonset.yaml"
    fi
}

function main() {
    VERSION=${1-}
    if [ -z "$VERSION" ]; then
        get_latest_version
    fi

    WEAVE_KUBE_IMAGE_PATCH_VERSION="$(get_images_patch_version "kurlsh/weave-kube")"
    WEAVE_NPC_IMAGE_PATCH_VERSION="$(get_images_patch_version "kurlsh/weave-npc")"
    WEAVE_EXEC_IMAGE_PATCH_VERSION="$(get_images_patch_version "kurlsh/weaveexec")"

    ADDON_VERSION="$(get_addon_version "$VERSION" "$WEAVE_KUBE_IMAGE_PATCH_VERSION" "$WEAVE_NPC_IMAGE_PATCH_VERSION" "$WEAVE_EXEC_IMAGE_PATCH_VERSION")"
    ADDON_VERSION="$(echo "$ADDON_VERSION" | sed -e 's/-[0-9a-f]\{7\}$//')"

    if [ -d "../$ADDON_VERSION" ]; then
        echo "Weave ${ADDON_VERSION} add-on already exists"
        exit 0
    fi

    generate

    add_as_latest

    echo "::set-output name=weave::$ADDON_VERSION"
}

main "$@"
