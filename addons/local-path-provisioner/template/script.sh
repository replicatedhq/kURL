#!/bin/bash
# this script assumes it is run within <kurl>/addons/local-path-provisioner/template

set -euo pipefail

VERSION=""

function get_latest_release_version() {
  VERSION=$(curl --silent "https://api.github.com/repos/rancher/local-path-provisioner/releases/latest" | # Get latest release from GitHub api
    grep '"tag_name":' |                                                                                  # Get tag line
    sed -E 's/.*"v([^"]+)".*/\1/'                                                                         # Pluck JSON value
  )
}

function generate() {
    # make the base set of files
    mkdir -p "../${VERSION}"
    cp -r ./base/* "../${VERSION}"

    # get the raw yaml for the release
    curl --silent "https://raw.githubusercontent.com/rancher/local-path-provisioner/v$VERSION/deploy/local-path-storage.yaml" > "../${VERSION}/local-path-provisioner.yaml"

    # change `busybox` to `busybox:1`
    sed -i "s/busybox/busybox:1/g" "../${VERSION}/local-path-provisioner.yaml"

    sed -i "s/__releasever__/${VERSION}/g" "../${VERSION}/install.sh"

    # get the images for the release
    echo "image local-path-provisioner rancher/local-path-provisioner:v${VERSION}" >> "../${VERSION}/Manifest"
}

function add_as_latest() {
    sed -i "/cron-local-path-provisioner-update/a\    \"${VERSION}\"\," ../../../web/src/installers/versions.js
}

function main() {
    get_latest_release_version

    if [ -d "../${VERSION}" ]; then
        if [ $# -ge 1 ] && [ "$1" == "force" ]; then
            echo "forcibly updating existing version of local-path-provisioner"
            rm -rf "../${VERSION}"
        else
            echo "not updating existing version of local-path-provisioner"
            return
        fi
    else
        add_as_latest
    fi

    generate

    echo "::set-output name=local-path-provisioner_version::$VERSION"
}

main "$@"
