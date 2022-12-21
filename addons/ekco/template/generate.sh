#!/bin/bash

set -euo pipefail

function get_latest_version() {
    docker run quay.io/skopeo/stable --override-os linux \
        list-tags "docker://replicated/ekco" | \
        jq -r '.Tags | .[]' | \
        grep '^v[0-9]*\.[0-9]*\.[0-9]*' | \
        grep -v '^v2[0-9]\{3\}' | \
        sed '/-/!{s/$/_/}' | sort -rV | sed 's/_$//' | \
        sed 's/^v//' | \
        head -n 1
}

function get_latest_haproxy_version() {
    docker run quay.io/skopeo/stable --override-os linux \
        list-tags "docker://library/haproxy" | \
        jq -r '.Tags | .[]' | \
        grep "^[0-9]*\.[0-9]*\.[0-9]*-alpine[0-9]*\.[0-9]*$" | \
        awk -F '-alpine' '{ print $1 " " $2 }' | \
        sort -rV -k1 -k2 | \
        awk 'NR == 1 { print $1 "-alpine" $2 }'
}

function generate() {
    local dir="../$VERSION"

    local haproxy_version=
    haproxy_version="$(get_latest_haproxy_version)"

    # make the base set of files
    mkdir -p "$dir"
    cp -r ./base/* "$dir"

    sed -i "s/__EKCO_VERSION__/$VERSION/g" "$dir/Manifest"
    sed -i "s/__EKCO_VERSION__/$VERSION/g" "$dir/deployment.yaml"
    sed -i "s/__HAPROXY_VERSION__/$haproxy_version/g" "$dir/Manifest"
    sed -i "s/__HAPROXY_VERSION__/$haproxy_version/g" "$dir/install.sh"
}

function add_as_latest() {
    if ! sed '0,/cron-ekco-update/d' ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -q "${VERSION}" ; then
        sed -i "/cron-ekco-update/a\    \"${VERSION}\"\," ../../../web/src/installers/versions.js
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

    local VERSION="$version_flag"
    if [ -z "$VERSION" ]; then
        VERSION="$(get_latest_version)"
    fi

    if [ -d "../$VERSION" ]; then
        if [ "$force_flag" == "1" ]; then
            echo "forcibly updating existing version of EKCO"
            rm -rf "../${VERSION}"
        else
            echo "not updating existing version of EKCO"
            return
        fi
    fi

    generate

    add_as_latest

    echo "::set-output name=ekco_version::$VERSION"
}

main "$@"
