#!/bin/bash

set -euo pipefail

# Keep generated runtime references and air-gap image manifests in sync.
function use_securebuild_images() {
    local dir="../$VERSION"
    [ "$VERSION" = "0.57.5" ] || return 0
    find "$dir" -type f \( -name Manifest -o -name '*.yaml' -o -name '*.sh' \) \
        -exec sed -i -E -f ./securebuild-images.sed {} +
}

function get_latest_release_version() {
    curl -sI https://github.com/vmware-tanzu/sonobuoy/releases/latest | \
        grep -i "^location" | \
        grep -Eo "0\.[0-9]+\.[0-9]+"
}

function generate() {
    mkdir -p "../${VERSION}"
    cp -r ./base/* "../${VERSION}"

    sed -i "s/__SONOBUOY_VERSION__/${VERSION}/g" "../${VERSION}/Manifest"

    # insert images into manifest
    local tmpdir=
    tmpdir="$(mktemp -d)"
    curl -sL -o "${tmpdir}/sonobuoy.tar.gz" https://github.com/vmware-tanzu/sonobuoy/releases/download/v${VERSION}/sonobuoy_${VERSION}_linux_amd64.tar.gz && \
        tar xzf "${tmpdir}/sonobuoy.tar.gz" -C "${tmpdir}"
    "${tmpdir}/sonobuoy" gen --kubernetes-version latest | \
        grep ' image: ' | \
        grep -v conformance | \
        sed 's/ *image: "*\(.*\)\/\(.*\):\([^"]*\)"*/image \2 \1\/\2:\3/' >> "../${VERSION}/Manifest"
    rm -r "${tmpdir}"
    use_securebuild_images
    local sonobuoy_image= systemd_logs_image=
    sonobuoy_image="$(awk '$1 == "image" && $2 == "sonobuoy" {print $3}' "../${VERSION}/Manifest")"
    systemd_logs_image="$(awk '$1 == "image" && $2 == "systemd-logs" {print $3}' "../${VERSION}/Manifest")"
    sed -i "s|__SONOBUOY_IMAGE__|$sonobuoy_image|g; s|__SYSTEMD_LOGS_IMAGE__|$systemd_logs_image|g" "../${VERSION}/sonobuoy.sh"
}

function add_as_latest() {
    if ! sed '0,/cron-sonobuoy-update/d' ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -q "${VERSION}" ; then
        sed -i "/cron-sonobuoy-update/a\    \"${VERSION}\"\," ../../../web/src/installers/versions.js
    fi
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

    local VERSION=
    if [ -n "$version_flag" ]; then
        VERSION="$version_flag"
    else
        VERSION="$(get_latest_release_version)"
    fi

    if [ -d "../$VERSION" ]; then
        if [ "$force_flag" == "1" ]; then
            echo "Forcibly updating existing version of Sonobuoy"
            rm -rf "../$VERSION"
        else
            echo "Sonobuoy $VERSION add-on already exists"
            exit 0
        fi
    fi

    generate

    add_as_latest

    echo "sonobuoy_version=$VERSION" >> "$GITHUB_OUTPUT"
}

main "$@"
