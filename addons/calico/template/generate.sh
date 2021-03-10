#!/bin/bash

set -euo pipefail

VERSION=""
function get_latest_release_version() {
    VERSION=$(curl https://docs.projectcalico.org/manifests/calico.yaml | \
        grep -E 'calico/cni:v3\.[0-9]+\.[0-9]+' | \
        head -1 | \
        awk -F'v' '{ print $NF }')
}

function generate() {
    cp -r ./base/* "../${VERSION}"

    sed -i "s/__CALICO_VERSION__/$VERSION/g" "../$VERSION/Manifest"

    curl https://docs.projectcalico.org/manifests/calico.yaml > "../${VERSION}/calico.yaml"
}

function add_as_latest() {
    sed -i "/cron-calico-update/a\      \"${VERSION}\"\," ../../../web/src/installers/index.ts
}

function main() {
    get_latest_release_version

    if [ -d "../${VERSION}" ]; then
        exit 0
    fi
    mkdir -p "../${VERSION}"

    generate

    add_as_latest

    echo "::set-output name=velero_version::$VERSION"
}

main "$@"
