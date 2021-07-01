#!/bin/bash

set -euo pipefail

VERSION=""
function get_latest_release_version() {
    VERSION=$(curl -I https://github.com/vmware-tanzu/sonobuoy/releases/latest | \
        grep -i "^location" | \
        grep -Eo "0\.[0-9]+\.[0-9]+")
}

function generate() {
    mkdir -p "../${VERSION}"
    cp -r ./base/* "../${VERSION}"

    sed -i "s/__SONOBUOY_VERSION__/${VERSION}/g" "../${VERSION}/Manifest"

    # insert images into manifest
    local tmpdir=
    tmpdir="$(mktemp -d)"
    curl -L -o "${tmpdir}/sonobuoy.tar.gz" https://github.com/vmware-tanzu/sonobuoy/releases/download/v${VERSION}/sonobuoy_${VERSION}_linux_amd64.tar.gz && \
        tar xzvf "${tmpdir}/sonobuoy.tar.gz" -C "${tmpdir}"
    "${tmpdir}/sonobuoy" gen --kube-conformance-image-version latest | \
        grep ' image: ' | \
        grep -v conformance | \
        sed 's/ *image: "*\(.*\)\/\(.*\):\([^"]*\)"*/image \2 \1\/\2:\3/' >> "../${VERSION}/Manifest"
    rm -r "${tmpdir}"
}

function add_as_latest() {
    if ! sed '0,/cron-sonobuoy-update/d' ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -q "${VERSION}" ; then
        sed -i "/cron-sonobuoy-update/a\    \"${VERSION}\"\," ../../../web/src/installers/versions.js
    fi
}

function main() {
    get_latest_release_version

    if [ -d "../${VERSION}" ]; then
        exit 0
    fi

    generate

    add_as_latest

    echo "::set-output name=sonobuoy_version::${VERSION}"
}

main "$@"
