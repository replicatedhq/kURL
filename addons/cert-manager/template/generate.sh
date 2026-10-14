#!/bin/bash

set -euo pipefail

# Keep older releases on upstream images; use SecureBuild from this release onward.
function use_securebuild_images() {
    local dir="../$CERT_MANAGER_VERSION"
    [ "$(printf '%s\n' "1.21.2" "$CERT_MANAGER_VERSION" | sort -V | head -n 1)" = "1.21.2" ] || return 0

    # Preserve component versions while translating repositories and packaging suffixes.
    local replacements=
    replacements="$(cat <<'SED'
/^[[:space:]]*#/b
s~(^|[[:space:]"'=])quay\.io/jetstack/cert-manager-controller:(v?[0-9][[:alnum:]._-]*)(@sha256:[[:xdigit:]]+)?~\1docker.io/kurlsh/cert-manager-controller:\2~g
s~(^|[[:space:]"'=])quay\.io/jetstack/cert-manager-cainjector:(v?[0-9][[:alnum:]._-]*)(@sha256:[[:xdigit:]]+)?~\1docker.io/kurlsh/cert-manager-cainjector:\2~g
s~(^|[[:space:]"'=])quay\.io/jetstack/cert-manager-webhook:(v?[0-9][[:alnum:]._-]*)(@sha256:[[:xdigit:]]+)?~\1docker.io/kurlsh/cert-manager-webhook:\2~g
s~(^|[[:space:]"'=])quay\.io/jetstack/cert-manager-acmesolver:(v?[0-9][[:alnum:]._-]*)(@sha256:[[:xdigit:]]+)?~\1docker.io/kurlsh/cert-manager-acmesolver:\2~g
SED
)"
    bash ../../../bin/verify-securebuild-images.sh "$dir/Manifest" "$replacements" || return 1
    # Leave the legacy v1.0.3 upgrade detection in install.sh on its original image.
    local file=
    while IFS= read -r -d '' file; do
        sed_i -E "$replacements" "$file"
    done < <(find "$dir" -type f \( -name Manifest -o -name '*.yaml' \) -print0)
}

# Portable sed -i function that works on both macOS and Linux
function sed_i() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS (BSD sed)
        sed -i '' "$@"
    else
        # Linux (GNU sed)
        sed -i "$@"
    fi
}

function get_latest_release_version() {
    VAR_NAME=$1
    local url=$2
    local version

    version=$(curl -sI "$url" | \
        grep -i "^location" | \
        grep -Eo "[0-9]+\.[0-9]+\.[0-9]+")

    export "$VAR_NAME=$version"
}

function download_cert_manager_yaml() {
    local url="https://github.com/cert-manager/cert-manager/releases/download/v${CERT_MANAGER_VERSION}/cert-manager.yaml"
    echo "Downloading cert-manager.yaml from $url"

    # Download and prepend comment in one step
    {
        echo "# downloaded from $url"
        echo ""
        curl -fsSL "$url"
    } > "../${CERT_MANAGER_VERSION}/cert-manager.yaml"
}

function generate() {
    mkdir -p "../${CERT_MANAGER_VERSION}"
    cp -r ./base/* "../${CERT_MANAGER_VERSION}"

    # Replace version placeholders in Manifest
    sed_i "s/__CERT_MANAGER_VERSION__/$CERT_MANAGER_VERSION/g" "../$CERT_MANAGER_VERSION/Manifest.tmpl"
    mv "../$CERT_MANAGER_VERSION/Manifest.tmpl" "../$CERT_MANAGER_VERSION/Manifest"

    # Replace version placeholders in install.sh
    sed_i "s/__CERT_MANAGER_VERSION__/$CERT_MANAGER_VERSION/g" "../$CERT_MANAGER_VERSION/install.tmpl.sh"
    mv "../$CERT_MANAGER_VERSION/install.tmpl.sh" "../$CERT_MANAGER_VERSION/install.sh"

    # Download the cert-manager.yaml from GitHub releases
    download_cert_manager_yaml
    use_securebuild_images
}

function add_as_latest() {
    local versions_file="../../../web/src/installers/versions.js"

    echo "Checking versions.js at: $versions_file"

    # Add the new version if it doesn't already exist in certManager section
    # Extract only the certManager array and check if version exists
    if ! awk '/certManager: \[/,/\],/' "$versions_file" | grep -q "\"${CERT_MANAGER_VERSION}\"" ; then
        echo "Adding version ${CERT_MANAGER_VERSION} to versions.js..."
        awk -v version="$CERT_MANAGER_VERSION" '/cron-cert-manager-update/ {print; print "    \"" version "\","; next}1' "$versions_file" > "$versions_file.tmp"
        mv "$versions_file.tmp" "$versions_file"
        echo "Version added successfully!"
    else
        echo "Version ${CERT_MANAGER_VERSION} already exists in versions.js"
    fi
}

CERT_MANAGER_VERSION=""
function main() {
    get_latest_release_version CERT_MANAGER_VERSION https://github.com/cert-manager/cert-manager/releases/latest

    echo "Found cert-manager version ${CERT_MANAGER_VERSION}"

    if [ -d "../${CERT_MANAGER_VERSION}" ]; then
        echo "Version ${CERT_MANAGER_VERSION} already exists, regenerating..."
        rm -rf "../${CERT_MANAGER_VERSION}"
    fi

    generate
    add_as_latest

    if [ -n "$GITHUB_OUTPUT" ]; then
        echo "cert_manager_version=$CERT_MANAGER_VERSION" >> "$GITHUB_OUTPUT"
    fi
    echo "cert_manager_version=$CERT_MANAGER_VERSION"
}

main "$@"
