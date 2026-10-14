#!/bin/bash

set -euo pipefail

# Keep older releases on upstream images; use SecureBuild from this release onward.
function use_securebuild_images() {
    local dir="../$VERSION"
    [ "$(printf '%s\n' "0.57.5" "$VERSION" | sort -V | head -n 1)" = "0.57.5" ] || return 0

    # Preserve component versions while translating repositories and packaging suffixes.
    local replacements=
    replacements="$(cat <<'SED'
/^[[:space:]]*#/b
s~(^|[[:space:]"'=])sonobuoy/sonobuoy:(v?[0-9][[:alnum:]._-]*)(@sha256:[[:xdigit:]]+)?~\1docker.io/kurlsh/sonobuoy:\2~g
s~(^|[[:space:]"'=])sonobuoy/systemd-logs:(v?[0-9][[:alnum:]._-]*)(@sha256:[[:xdigit:]]+)?~\1docker.io/kurlsh/sonobuoy-systemd-logs:\2~g
SED
)"
    bash ../../../bin/verify-securebuild-images.sh "$dir/Manifest" "$replacements" || return 1
    find "$dir" -type f \( -name Manifest -o -name '*.yaml' -o -name '*.sh' \) \
        -exec sed -i -E "$replacements" {} +
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
    sonobuoy_configure_image_defaults
}

function sonobuoy_configure_image_defaults() {
    local sonobuoy_image= systemd_logs_image=
    sonobuoy_image="$(awk '$1 == "image" && $2 == "sonobuoy" && NF == 3 {print $3}' "../${VERSION}/Manifest")" || return 1
    systemd_logs_image="$(awk '$1 == "image" && $2 == "systemd-logs" && NF == 3 {print $3}' "../${VERSION}/Manifest")" || return 1

    # Classify by version, then validate both image entries. Missing or malformed
    # references must not silently select the historical CLI installation path.
    local securebuild_release=0
    local sonobuoy_repository='(docker[.]io/)?sonobuoy/sonobuoy'
    local systemd_logs_repository='(docker[.]io/)?sonobuoy/systemd-logs'
    if [ "$(printf '%s\n' "0.57.5" "$VERSION" | sort -V | head -n 1)" = "0.57.5" ]; then
        securebuild_release=1
        sonobuoy_repository='docker[.]io/kurlsh/sonobuoy'
        systemd_logs_repository='docker[.]io/kurlsh/sonobuoy-systemd-logs'
    fi
    local tag_pattern='[[:alnum:]_][[:alnum:]_.-]*(@sha256:[[:xdigit:]]{64})?'
    if ! [[ "$sonobuoy_image" =~ ^${sonobuoy_repository}:${tag_pattern}$ ]]; then
        echo "Missing or invalid sonobuoy image in ../${VERSION}/Manifest: $sonobuoy_image" >&2
        return 1
    fi
    if ! [[ "$systemd_logs_image" =~ ^${systemd_logs_repository}:${tag_pattern}$ ]]; then
        echo "Missing or invalid systemd-logs image in ../${VERSION}/Manifest: $systemd_logs_image" >&2
        return 1
    fi

    if [ "$securebuild_release" = "1" ]; then
        sed -i "s|__SONOBUOY_IMAGE__|$sonobuoy_image|g; s|__SYSTEMD_LOGS_IMAGE__|$systemd_logs_image|g" "../${VERSION}/sonobuoy.sh"
    else
        # Historical releases retain their original CLI installation and defaults.
        rm -f "../${VERSION}/sonobuoy.sh"
    fi
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
