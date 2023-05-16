#!/bin/bash

set -euo pipefail

function generate() {
    local dir="../$version"

    mkdir -p "$dir"

    cp -r ./base/* "$dir"

    download_yaml
    replace_flannel_image_with_version
    find_images_in_yaml
}

function replace_flannel_image_with_version() {
    sed -E -i "s/docker\.io\/flannel\/flannel:.*/docker\.io\/flannel\/flannel:v$version/g" "$dir/yaml/kube-flannel.yml"
}

function download_yaml() {
    curl -Lo "$dir/yaml/kube-flannel.yml" "https://raw.githubusercontent.com/flannel-io/flannel/v$version/Documentation/kube-flannel.yml"
}

function find_images_in_yaml() {
    grep ' image: '  "$dir/yaml/kube-flannel.yml" | \
        sed -E 's/ *image: "*([^\/]+\/)?([^\/]+)\/([^:]+):([^" ]+).*/image \2-\3 \1\2\/\3:\4/' | \
        sort | uniq >> "${dir}/Manifest"
}

function get_latest_release_version() {
    curl -I "https://github.com/flannel-io/flannel/releases/latest" | \
        grep -i "^location" | \
        grep -Eo "[0-9]+\.[0-9]+\.[0-9]+"
}

function add_as_latest() {
    if ! sed "0,/cron-flannel-update/d" ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -q "$version" ; then
        sed -i "/cron-flannel-update$/a\    \"$version\"\," ../../../web/src/installers/versions.js
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

    local version=
    if [ -n "$version_flag" ]; then
        version="$version_flag"
    else
        version="$(get_latest_release_version)"
    fi

    if [ -d "../$version" ]; then
        if [ "$force_flag" == "1" ]; then
            echo "forcibly updating existing version of flannel"
            rm -rf "../$version"
        else
            echo "not updating existing version of flannel"
            return
        fi
    fi

    generate "$version"
    add_as_latest "$version"

    echo "flannel_version=$version" >> "$GITHUB_OUTPUT"
}

main "$@"
