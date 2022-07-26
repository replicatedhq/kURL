#!/bin/bash

set -euo pipefail

VERSION=""

function get_latest_release_version() {
    VERSION="$(docker run quay.io/skopeo/stable --override-os linux \
        list-tags "docker://replicated/ekco" | \
        jq -r '.Tags | .[]' | \
        grep '^v[0-9]*\.[0-9]*\.[0-9]*' | \
        grep -v '^v2[0-9]\{3\}' | \
        sed '/-/!{s/$/_/}' | sort -rV | sed 's/_$//' | \
        sed 's/^v//' | \
        head -n 1
    )"
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
    local dir="../${VERSION}"

    local haproxy_version="$(get_latest_haproxy_version)"

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

function main() {
    VERSION="${1:-}"

    if [ -z "${VERSION}" ]; then
        get_latest_release_version
    fi

    if [ -d "../${VERSION}" ]; then
        if [ "${1:-}" = "force" ] || [ "${2:-}" = "force" ]; then
            echo "forcibly updating existing version of ekco"
            rm -rf "../${VERSION}"
        else
            echo "not updating existing version of ekco"
            return
        fi
    fi

    generate

    add_as_latest

    echo "::set-output name=ekco_version::$VERSION"
}

main "$@"
