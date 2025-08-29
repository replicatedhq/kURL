#!/bin/bash

set -euo pipefail

VERSION=""
CHARTVERSION=""

function add_as_latest() {
    if ! grep -q "\"${VERSION}-${CHARTVERSION}\"" ../../../web/src/installers/versions.js; then
        sed -i '' "/cron-goldpinger-update/a\\    \"${VERSION}-${CHARTVERSION}\"," ../../../web/src/installers/versions.js
    fi
}

function get_latest_bloomberg_version() {
    # Get latest versions from Bloomberg chart
    VERSION=$(helm show chart goldpinger/goldpinger | \
        grep -i "^appVersion" | \
        grep -Eo "[0-9]\.[0-9]+\.[0-9]+")
    CHARTVERSION=$(helm show chart goldpinger/goldpinger | \
        grep -i "^version" | \
        grep -Eo "[0-9]+\.[0-9]+\.[0-9]+")
}

function generate_bloomberg_dynamic() {
    # Make the base set of files
    mkdir -p "../${VERSION}-${CHARTVERSION}"
    cp -r ./base/* "../${VERSION}-${CHARTVERSION}"
    
    # Get a copy of the stack using Bloomberg chart
    helm template goldpinger goldpinger/goldpinger --version "$CHARTVERSION" --values ./values-bloomberg.yaml -n kurl --include-crds > "../$VERSION-$CHARTVERSION/goldpinger.yaml"
    
    # Update version placeholders in install.sh (always use canonical template)
    sed -i '' "s/__GOLDPINGER_VERSION__/$VERSION-$CHARTVERSION/g" "../$VERSION-$CHARTVERSION/install.sh"
    
    # Generate manifest with Bloomberg image
    grep 'image: '  "../$VERSION-$CHARTVERSION/goldpinger.yaml" | sed 's/ *image: "*\(.*\)\/\(.*\):\([^"]*\)"*/image \2 \1\/\2:\3/' > "../$VERSION-$CHARTVERSION/Manifest"
    
    echo "Generated Bloomberg goldpinger version: $VERSION-$CHARTVERSION"
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
    
    # Use Bloomberg chart (official chart going forward)
    helm repo add goldpinger https://bloomberg.github.io/goldpinger
    helm repo update
    
    # Get versions
    if [ -n "$version_flag" ]; then
        VERSION="$( echo "$version_flag" | cut -d'-' -f1 )"
        CHARTVERSION="$( echo "$version_flag" | cut -d'-' -f2 )"
    else
        get_latest_bloomberg_version
    fi

    if [ -d "../${VERSION}-${CHARTVERSION}" ]; then
        if [ "$force_flag" == "1" ]; then
            echo "forcibly updating existing version of goldpinger"
            rm -rf "../${VERSION}-${CHARTVERSION}"
        else
            echo "not updating existing version of goldpinger"
            return
        fi
    else
        add_as_latest
    fi

    generate_bloomberg_dynamic

    if [ -n "${GITHUB_OUTPUT:-}" ]; then
        echo "goldpinger_version=$VERSION-$CHARTVERSION" >> "$GITHUB_OUTPUT"
    fi
}

main "$@"
