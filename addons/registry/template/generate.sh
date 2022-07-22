#!/bin/bash

set -euo pipefail

VERSION=
function get_latest_version() {
    VERSION=$(curl -s https://api.github.com/repos/distribution/distribution/releases/latest | \
        grep '"tag_name":' | \
        sed -E 's/.*"([^"]+)".*/\1/' | \
        sed 's/v//')
}

S3CMD_TAG=
function s3cmd_get_tag() {
    S3CMD_TAG="$(. ../../../bin/s3cmd-get-latest-tag.sh)"
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
    sed -i "s/__S3CMD_TAG__/$S3CMD_TAG/g" "../$VERSION/Manifest"
    sed -i "s/__S3CMD_TAG__/$S3CMD_TAG/g" "../$VERSION/patch-deployment-migrate-s3.yaml"
    sed -i "s/__S3CMD_TAG__/$S3CMD_TAG/g" "../$VERSION/patch-deployment-velero.yaml"
}

function add_as_latest() {
    if ! sed '0,/cron-registry-update/d' ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -q "${VERSION}" ; then
        sed -i "/cron-registry-update/a\    \"${VERSION}\"\," ../../../web/src/installers/versions.js
    fi
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

    s3cmd_get_tag

    generate

    echo "::set-output name=registry_version::$VERSION"
}

main "$@"
