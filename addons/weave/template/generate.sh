#!/bin/bash

set -euo pipefail

VERSION=
function get_latest_version() {
    VERSION=$(curl -s https://api.github.com/repos/weaveworks/weave/releases/latest | \
        grep '"name":' | \
        grep -Eo "[0-9]+\.[0-9]+\.[0-9]+" | \
        head -1)
}

function add_as_latest() {
    sed -i "/cron-weave-update/a\    \"${VERSION}\"\," ../../../web/src/installers/versions.js
}

function generate() {
    local dir="../${VERSION}"

    mkdir -p "$dir"

    cp -r base/* "$dir/"
    sed -i "s/__WEAVE_VERSION__/$VERSION/g" "$dir/Manifest"

    curl -L --fail "https://github.com/weaveworks/weave/releases/download/v$VERSION/weave-daemonset-k8s-1.11.yaml" \
        > "$dir/weave-daemonset-k8s-1.11.yaml"
}

function main() {
    VERSION=${1-}
    if [ -z "$VERSION" ]; then
        get_latest_version
    fi

    if [ -d "../$VERSION" ]; then
        echo "Weave ${VERSION} add-on already exists"
        exit 0
    fi

    generate

    add_as_latest

    echo "::set-output name=weave::$VERSION"
}

main "$@"
