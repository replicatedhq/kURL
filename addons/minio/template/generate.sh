#!/bin/bash

set -euo pipefail

VERSION=
function get_latest_version() {
    VERSION=$(curl -s https://api.github.com/repos/minio/minio/releases/latest | \
        grep '"tag_name":' | \
        sed -E 's/.*"([^"]+)".*/\1/')
}

function add_as_latest() {
    sed -i "/cron-minio-update/a\    \"${DIR_NAME}\"\," ../../../web/src/installers/versions.js
}

function generate() {
    local dir="../${DIR_NAME}"

    mkdir -p "$dir"
    cp -r base/* "$dir/"

    sed -i "s/__MINIO_VERSION__/$VERSION/g" "$dir/Manifest"
    sed -i "s/__MINIO_VERSION__/$VERSION/g" "$dir/deployment.yaml"
    sed -i "s/__MINIO_VERSION__/$VERSION/g" "$dir/migrate-fs/pvc/deployment.yaml"
    sed -i "s/__MINIO_VERSION__/$VERSION/g" "$dir/migrate-fs/hostpath/deployment.yaml"
    sed -i "s/__MINIO_VERSION__/$VERSION/g" "$dir/install.sh"
    sed -i "s/__MINIO_VERSION__/$VERSION/g" "$dir/tmpl-ha-statefulset.yaml"

    sed -i "s/__MINIO_DIR_NAME__/$DIR_NAME/g" "$dir/install.sh"
}

function main() {
    VERSION=${1-}
    if [ -z "$VERSION" ]; then
        get_latest_version
    fi

    DIR_NAME=${VERSION#"RELEASE."}

    if [ -d "../${DIR_NAME}" ]; then
        echo "MinIO ${VERSION} add-on already exists"
        exit 0
    fi

    generate

    add_as_latest

    echo "minio_version=$VERSION" >> "$GITHUB_OUTPUT"
}

main "$@"
