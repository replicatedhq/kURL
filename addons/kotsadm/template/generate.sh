#!/bin/bash

set -euo pipefail

function require() {
   if [ -z "$2" ]; then
       echo "validation failed: $1 unset"
       exit 1
   fi
}

# From Client Payload
require KOTSADM_VERSION "${KOTSADM_VERSION}"

function generate() {
    local kotsadm_tag=$1
    local kotsadm_dir=$2
    local kotsadm_binary_version=$3
    local dir="../${kotsadm_dir}"\

    if [ -d "$dir" ]; then
        echo "Kotsadm ${kotsadm_dir} add-on already exists"
        
        # Clean out the directory in case the template has removed any files
        rm -rf "$dir"
    fi
    mkdir -p "$dir"

    cp -r base/* "$dir/"
    find "$dir" -type f -exec sed -i -e "s/__KOTSADM_TAG__/$kotsadm_tag/g" {} \;
    find "$dir" -type f -exec sed -i -e "s/__KOTSADM_DIR__/$kotsadm_dir/g" {} \;
    find "$dir" -type f -exec sed -i -e "s/__KOTSADM_BINARY_VERSION__/$kotsadm_binary_version/g" {} \;

}

function add_as_latest() {
    local kotsadm_dir="$1"
    sed -i "/auto-kotsadm-update/a\    \"${kotsadm_dir}\"\," ../../../web/src/installers/versions.js
}

function upsert_kotsadm_version(){
    true
}

function main() {

    case "$KOTSADM_VERSION" in
        # catch accidental typos
        "v"*)
            echo "KOTSADM_VERSION should not start with the 'v' prefix"
            exit 1
            ;;
        *"beta"*)
            echo "generating beta version"
            generate "alpha" "alpha" "v$KOTSADM_VERSION"
            ;;
        *)
            # Check for a new release, if so make it latest in the web and also create a new alpha
            if [ ! -d "../$KOTSADM_VERSION" ]; then
                add_as_latest "$KOTSADM_VERSION"
                echo "generating alpha version"
                generate "alpha" "alpha" "v$KOTSADM_VERSION"
            fi

            echo "generating v$KOTSADM_VERSION version"
            generate "v$KOTSADM_VERSION" "$KOTSADM_VERSION" "v$KOTSADM_VERSION"
            ;;
    esac

    echo "::set-output name=kotsadm_version::$KOTSADM_VERSION"
}

main "$@"
