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

function add_as_latest() {
    sed -i "/cron-goldpinger-update/a\    \"${VERSION}-${CHARTVERSION}\"\," ../../../web/src/installers/versions.js
}

function main() {
    # run the helm commands
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
