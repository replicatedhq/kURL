#!/bin/bash

set -euo pipefail

function get_latest_version() {
    VERSION=$(curl -s https://api.github.com/repos/distribution/distribution/releases/latest | \
        grep '"tag_name":' | \
        sed -E 's/.*"([^"]+)".*/\1/' | \
        sed 's/v//')
}

function get_s3cmd_tag() {
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

VERSION=""
S3CMD_TAG=""
function main() {
    get_latest_version
    get_s3cmd_tag

    echo "Found Registry version ${VERSION}"
    echo "Found kurlsh/s3cmd tag ${S3CMD_TAG}"

    local IS_NEW_VERSION=1
    if [ -d "../${VERSION}" ]; then
        rm -rf "../${VERSION}"
        IS_NEW_VERSION=0
    fi

    generate

    if [ "$IS_NEW_VERSION" == "1" ] ; then
        add_as_latest
    fi

    echo "registry_version=$VERSION" >> "$GITHUB_OUTPUT"
}

main "$@"
