#!/bin/bash

set -euo pipefail

VERSION=""
function get_latest_release_version() {
    VERSION=$(curl -I https://github.com/vmware-tanzu/velero/releases/latest | \
        grep -i "^location" | \
        grep -Eo "1\.[0-9]+\.[0-9]+")
}

function generate() {
    mkdir -p "../${VERSION}"
    cp -r ./base/* "../${VERSION}"

    sed -i "s/__VELERO_VERSION__/$VERSION/g" "../$VERSION/Manifest"
}

function add_as_latest() {
    sed -i "/cron-velero-update/a\      \"${VERSION}\"\," ../../../web/src/installers/index.ts
}

function main() {
    get_latest_release_version

    if [ -d "../${VERSION}" ]; then
        exit 0
    fi

    generate

    add_as_latest

    echo "::set-output name=velero_version::$VERSION"
}

main "$@"
