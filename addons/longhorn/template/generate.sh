#!/bin/bash

set -euo pipefail

VERSION=""

function get_latest_release_version() {
  VERSION=$(curl --silent "https://api.github.com/repos/longhorn/longhorn/releases/latest" | # Get latest release from GitHub api
    grep '"tag_name":' |                                                                     # Get tag line
    sed -E 's/.*"v([^"]+)".*/\1/'                                                             # Pluck JSON value
  )
}

KSPLITPATH=""
function getKsplit() {
    go install github.com/go-ksplit/ksplit/ksplit@v1.0.1
    KSPLITPATH="$GOPATH/bin/ksplit"
}

function generate() {
    # make the base set of files
    mkdir -p "../${VERSION}"
    mkdir -p "../${VERSION}/yaml"
    cp -r ./base/* "../${VERSION}"

    # get the raw yaml for the release
    curl --silent "https://raw.githubusercontent.com/longhorn/longhorn/v$VERSION/deploy/longhorn.yaml" > "../${VERSION}/yaml/longhorn.yaml"

    # cd to allow ksplit to include the path, and then cd back
    cd ..
    $KSPLITPATH crdsplit "${VERSION}/yaml/"
    cd template

    mv "../${VERSION}/yaml/AllResources.yaml" "../${VERSION}/AllResources.yaml"
    mv "../${VERSION}/yaml/CustomResourceDefinitions.yaml" "../${VERSION}/crds.yaml"
    rmdir "../${VERSION}/yaml"
}

function add_as_latest() {
    gsed -i "/cron-longhorn-update/a\    \"${VERSION}\"\," ../../../web/src/installers/versions.js
}

function main() {
    get_latest_release_version

    if [ -d "../${VERSION}" ]; then
        if [ $# -ge 1 ] && [ "$1" == "force" ]; then
            echo "forcibly updating existing version of longhorn"
            rm -rf "../${VERSION}"
        else
            echo "not updating existing version of longhorn"
            return
        fi
    else
        add_as_latest
    fi

    getKsplit

    generate

    echo "::set-output name=longhorn_version::$VERSION"
}

main "$@"
