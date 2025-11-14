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

function parse_flags() {
    for i in "$@"; do
        case ${1} in
            --force)
                force_flag="1"
                shift
                ;;
            --version=*)
                version_flag="${i#*=}"
                shift
                ;;
            *)
                echo "Unknown flag $1"
                exit 1
                ;;
        esac
    done
}

function main() {
    local force_flag=
    local version_flag=

    parse_flags "$@"

    VERSION="$version_flag"
    if [ -z "$VERSION" ]; then
        get_latest_version
    fi

    DIR_NAME=${VERSION#"RELEASE."}

    if [ -d "../$VERSION" ]; then
        if [ "$force_flag" == "1" ]; then
            echo "forcibly updating existing version of MinIO"
            rm -rf "../$VERSION"
        else
            echo "not updating existing version of MinIO"
            return
        fi
    fi

    generate

    add_as_latest

    echo "minio_version=$VERSION" >> "$GITHUB_OUTPUT"
}

main "$@"
