#!/bin/bash

set -euo pipefail

# Keep older releases on upstream images; use SecureBuild from this release onward.
function use_securebuild_images() {
    local dir="../$VERSION"
    [ "$(printf '%s\n' "0.28.17" "$VERSION" | sort -V | head -n 1)" = "0.28.17" ] || return 0

    # Preserve component versions while translating repositories and packaging suffixes.
    local replacements=
    replacements="$(cat <<'SED'
/^[[:space:]]*#/b
s~(^|[[:space:]"'=])haproxy:(v?[0-9][[:alnum:]._-]*)(@sha256:[[:xdigit:]]+)?~\1docker.io/kurlsh/haproxy:\2~g
s~(docker\.io/kurlsh/haproxy:[0-9][[:alnum:]._-]*)-alpine[0-9]+\.[0-9]+~\1~g
SED
)"
    bash ../../../bin/verify-securebuild-images.sh "$dir/Manifest" "$replacements" || return 1
    find "$dir" -type f \( -name Manifest -o -name '*.yaml' -o -name '*.sh' \) \
        -exec sed -i -E "$replacements" {} +
}

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

# The haproxy major version this add-on tracks. Bumping it is an explicit decision:
# a new haproxy major can change internal load balancer behaviour, so the cron must
# not adopt one on its own. Update this constant to move to the next major.
HAPROXY_MAJOR_VERSION="3"

function get_latest_haproxy_version() {
    docker run quay.io/skopeo/stable --override-os linux \
        list-tags "docker://library/haproxy" | \
        jq -r '.Tags | .[]' | \
        grep "^${HAPROXY_MAJOR_VERSION}\.[0-9]*\.[0-9]*-alpine[0-9]*\.[0-9]*$" | \
        awk -F '-alpine' '{ print $1 " " $2 }' | \
        sort -rV -k1 -k2 | \
        awk 'NR == 1 { print $1 "-alpine" $2 }'
}

function generate() {
    local dir="../$VERSION"

    # make the base set of files
    mkdir -p "$dir"
    cp -r ./base/* "$dir"

    sed -i "s/__EKCO_VERSION__/$VERSION/g" "$dir/Manifest"
    sed -i "s/__EKCO_VERSION__/$VERSION/g" "$dir/deployment.tmpl.yaml"
    sed -i "s/__HAPROXY_VERSION__/$HAPROXY_VERSION/g" "$dir/Manifest"
    sed -i "s/__HAPROXY_VERSION__/$HAPROXY_VERSION/g" "$dir/install.sh"
    use_securebuild_images
}

function add_as_only_version() {
    sed -i "/cron-ekco-update/c\    \"${VERSION}\", \/\/ cron-ekco-update" ../../../web/src/installers/versions.js
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

function remove_previous_versions() {
    local previous_versions=
    previous_versions="$(ls .. | grep '0.')"
    echo "removing previous versions $previous_versions"
    for version in $previous_versions; do
        rm -rf "../$version"
    done
    echo "removed previous ekco versions"
}

function main() {
    local force_flag=
    local version_flag=

    parse_flags "$@"

    local VERSION="$version_flag"
    if [ -z "$VERSION" ]; then
        VERSION="$(get_latest_version)"
    fi

    local HAPROXY_VERSION=
    HAPROXY_VERSION="$(get_latest_haproxy_version)"
    if [ -z "$HAPROXY_VERSION" ]; then
        echo "failed to find a haproxy ${HAPROXY_MAJOR_VERSION}.x alpine tag"
        exit 1
    fi

    remove_previous_versions

    generate

    add_as_only_version

    echo "ekco_version=$VERSION" >> "$GITHUB_OUTPUT"
    echo "haproxy_version=$HAPROXY_VERSION" >> "$GITHUB_OUTPUT"
}

main "$@"
