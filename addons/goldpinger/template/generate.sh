#!/bin/bash

set -euo pipefail

VERSION=""
function get_latest_release_version() {
    VERSION=$(helm show chart okgolove/goldpinger | \
        grep -i "^appVersion" | \
        grep -Eo "[0-9]\.[0-9]+\.[0-9]+")
    CHARTVERSION=$(helm show chart okgolove/goldpinger | \
        grep -i "^version" | \
        grep -Eo "[0-9]+\.[0-9]+\.[0-9]+")
}

function generate() {
    # make the base set of files
    mkdir -p "../${VERSION}-${CHARTVERSION}"
    cp -r ./base/* "../${VERSION}-${CHARTVERSION}"

    # get a copy of the stack
    helm template goldpinger okgolove/goldpinger --version "$CHARTVERSION" --values ./values.yaml -n kurl --include-crds > "../$VERSION-$CHARTVERSION/goldpinger.yaml"

    # update version in install.sh
    sed -i "s/__GOLDPINGER_VERSION__/$VERSION-$CHARTVERSION/g" "../$VERSION-$CHARTVERSION/install.sh"

    grep 'image: '  "../$VERSION-$CHARTVERSION/goldpinger.yaml" | sed 's/ *image: "*\(.*\)\/\(.*\):\([^"]*\)"*/image \2 \1\/\2:\3/' >> "../$VERSION-$CHARTVERSION/Manifest"
}

function generate_bloomberg() {
    # Generate Bloomberg chart version 3.10.2-1.0.1
    local VERSION="3.10.2"
    local CHARTVERSION="1.0.1"
    
    # Make the base set of files
    mkdir -p "../${VERSION}-${CHARTVERSION}"
    cp -r ./base/* "../${VERSION}-${CHARTVERSION}"
    
    # Get a copy of the stack using Bloomberg chart
    helm template goldpinger goldpinger/goldpinger --version "$CHARTVERSION" --values ./values-bloomberg.yaml -n kurl --include-crds > "../$VERSION-$CHARTVERSION/goldpinger.yaml"
    
    # Update version in install.sh
    sed -i "s/__GOLDPINGER_VERSION__/$VERSION-$CHARTVERSION/g" "../$VERSION-$CHARTVERSION/install.sh"
    
    # Generate manifest with Bloomberg image
    grep 'image: '  "../$VERSION-$CHARTVERSION/goldpinger.yaml" | sed 's/ *image: "*\(.*\)\/\(.*\):\([^"]*\)"*/image \2 \1\/\2:\3/' >> "../$VERSION-$CHARTVERSION/Manifest"
    
    echo "Generated Bloomberg goldpinger version: $VERSION-$CHARTVERSION"
}

function add_as_latest() {
    sed -i "/cron-goldpinger-update/a\    \"${VERSION}-${CHARTVERSION}\"\," ../../../web/src/installers/versions.js
}

function main_bloomberg() {
    # Generate Bloomberg chart 3.10.2-1.0.1
    local VERSION="3.10.2"
    local CHARTVERSION="1.0.1"
    
    # Add Bloomberg chart repo
    helm repo add goldpinger https://bloomberg.github.io/goldpinger
    helm repo update
    
    if [ -d "../${VERSION}-${CHARTVERSION}" ]; then
        if [ $# -ge 1 ] && [ "$1" == "force" ]; then
            echo "forcibly updating existing Bloomberg version of goldpinger"
            rm -rf "../${VERSION}-${CHARTVERSION}"
        else
            echo "not updating existing Bloomberg version of goldpinger"
            return
        fi
    fi
    
    generate_bloomberg
    
    echo "goldpinger_version=$VERSION-$CHARTVERSION" >> "$GITHUB_OUTPUT"
}

function main() {
    # Check if Bloomberg chart generation is requested
    if [ $# -ge 1 ] && [ "$1" == "bloomberg" ]; then
        shift
        main_bloomberg "$@"
        return
    fi
    
    # run the helm commands for okgolove
    helm repo add okgolove https://okgolove.github.io/helm-charts/
    helm repo update

    get_latest_release_version

    if [ -d "../${VERSION}-${CHARTVERSION}" ]; then
        if [ $# -ge 1 ] && [ "$1" == "force" ]; then
            echo "forcibly updating existing version of goldpinger"
            rm -rf "../${VERSION}-${CHARTVERSION}"
        else
            echo "not updating existing version of goldpinger"
            return
        fi
    else
        add_as_latest
    fi

    generate

    echo "goldpinger_version=$VERSION-$CHARTVERSION" >> "$GITHUB_OUTPUT"
}

main "$@"
