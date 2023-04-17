#!/bin/bash

set -euo pipefail

VERSION=
ADDON_VERSION=
WEAVE_KUBE_IMAGE_PATCH_VERSION=
WEAVE_NPC_IMAGE_PATCH_VERSION=
WEAVE_EXEC_IMAGE_PATCH_VERSION=

function get_images_patch_version() {
    local image="$1"
    docker run quay.io/skopeo/stable --override-os linux \
        list-tags "docker://${image}" | \
        jq -r '.Tags | .[]' | \
        grep -F "${VERSION}" | \
        grep -E "\-2[0-9]{7}-" | \
        sort -r | \
        head -n1
}

function get_addon_version() {
    local versions="$*"
    # sort in reverse to get the newest version and strip off the git sha suffix
    echo "$versions" | xargs -n1 | sort -r | xargs \
        | awk '{print $1}' \
        | sed -e 's/-[0-9a-f]\{7\}$//'
}

function add_as_latest() {
    if echo "${ADDON_VERSION}" | grep -Fq "2.6.5" ; then
        if ! sed '0,/cron-weave-update-265/d' ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -Fq "${ADDON_VERSION}" ; then
            sed -i "/cron-weave-update-265/a\    \"${ADDON_VERSION}\"\," ../../../web/src/installers/versions.js
        fi
    else
        if ! sed '0,/cron-weave-update-281/d' ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -Fq "${ADDON_VERSION}" ; then
            sed -i "/cron-weave-update-281/a\    \"${ADDON_VERSION}\"\," ../../../web/src/installers/versions.js
        fi
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
        VERSION=2.8.1
    fi
    if [ "$VERSION" != "2.6.5" ] && [ "$VERSION" != "2.8.1" ]; then
        echo "Weave versions 2.6.5 and 2.8.1 are supported"
        echo "Unsupported weave version: $VERSION"
        exit 1
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

    echo "::set-output name=weave_version::$ADDON_VERSION"
    echo "::set-output name=weave_major_minor_version::$(echo "$ADDON_VERSION" | awk -F'.' '{ print $1 "." $2 }')"
}

main "$@"
