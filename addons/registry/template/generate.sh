#!/bin/bash

set -euo pipefail

VERSION=
function get_latest_version() {
    VERSION=$(curl -s https://api.github.com/repos/distribution/distribution/releases/latest | \
        grep '"tag_name":' | \
        sed -E 's/.*"([^"]+)".*/\1/' | \
        sed 's/v//')
}

function generate() {
    # make the base set of files
    mkdir -p "../${VERSION}"
    cp -r ./base/* "../${VERSION}"

    # update version in files
    sed -i "s/__registry_version__/$VERSION/g" "../$VERSION/Manifest"
    sed -i "s/__registry_version__/$VERSION/g" "../$VERSION/install.sh"
    sed -i "s/__registry_version__/$VERSION/g" "../$VERSION/deployment-pvc.yaml"
    sed -i "s/__registry_version__/$VERSION/g" "../$VERSION/tmpl-deployment-objectstore.yaml"
}

function add_as_latest() {
    sed -i "/cron-registry-update/a\    \"${VERSION}\"\," ../../../web/src/installers/versions.js
}

function main() {
    get_latest_version

    if [ -d "../${VERSION}" ]; then
        if [ $# -ge 1 ] && [ "$1" == "force" ]; then
            echo "forcibly updating existing version of registry"
            rm -rf "../${VERSION}"
        else
            echo "not updating existing version of registry"
            return
        fi
    else
        add_as_latest
    fi

    generate

    echo "::set-output name=registry_version::$VERSION"
}

main "$@"
