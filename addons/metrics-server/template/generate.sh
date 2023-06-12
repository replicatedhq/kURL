#!/bin/bash

set -euo pipefail

function generate() {
    local dir="../$version"

    mkdir -p "$dir"

    cp -r ./base/* "$dir"

    sed -i "s/__METRICS_VERSION__/$version/g" "$dir/install.sh"

    download_yaml

    find_images_in_yaml
}

function download_yaml() {
    curl -Lo "$dir/components.yaml" "https://github.com/kubernetes-sigs/metrics-server/releases/download/v$version/components.yaml"
}

function find_images_in_yaml() {
    grep ' image: '  "$dir/components.yaml" | \
        sed -E 's/ *image: "*([^\/]+\/)?([^\/]+)\/([^:]+):([^" ]+).*/image \2-\3 \1\2\/\3:\4/' | \
        sort | uniq >> "${dir}/Manifest"
}

function get_latest_release_version() {
    curl https://api.github.com/repos/kubernetes-sigs/metrics-server/releases | \
        grep tag_name | \
        grep -v helm-chart | \
        grep -Eo "[0-9]+\.[0-9]+\.[0-9]+" | \
        head -n 1
}

function add_as_latest() {
    if ! sed "0,/cron-metrics-server-update/d" ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -q "$version" ; then
        sed -i "/cron-metrics-server-update$/a\    \"$version\"\," ../../../web/src/installers/versions.js
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
            echo "forcibly updating existing version of metrics-server"
            rm -rf "../$version"
        else
            echo "not updating existing version of metrics-server"
            return
        fi
    fi

    generate "$version"
    add_as_latest "$version"

    echo "metrics_server_version=$version" >> "$GITHUB_OUTPUT"
}

main "$@"
