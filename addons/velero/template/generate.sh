#!/bin/bash

set -euo pipefail

function get_latest_release_version() {
    VAR_NAME=$1 
    local url=$2 
    local version

    version=$(curl -I "$url" | \
        grep -i "^location" | \
        grep -Eo "1\.[0-9]+\.[0-9]+")

    declare -g "$VAR_NAME=$version"
}

function generate() {
    mkdir -p "../${VELERO_VERSION}"
    cp -r ./base/* "../${VELERO_VERSION}"

    sed -i "s/__VELERO_VERSION__/$VELERO_VERSION/g" "../$VELERO_VERSION/Manifest.tmpl"
    sed -i "s/__AWS_PLUGIN_VERSION__/$AWS_PLUGIN_VERSION/g" "../$VELERO_VERSION/Manifest.tmpl"
    sed -i "s/__AZURE_PLUGIN_VERSION__/$AZURE_PLUGIN_VERSION/g" "../$VELERO_VERSION/Manifest.tmpl"
    sed -i "s/__GCP_PLUGIN_VERSION__/$GCP_PLUGIN_VERSION/g" "../$VELERO_VERSION/Manifest.tmpl"
    mv "../$VELERO_VERSION/Manifest.tmpl" "../$VELERO_VERSION/Manifest"

    sed -i "s/__AWS_PLUGIN_VERSION__/$AWS_PLUGIN_VERSION/g" "../$VELERO_VERSION/install.sh.tmpl"
    sed -i "s/__AZURE_PLUGIN_VERSION__/$AZURE_PLUGIN_VERSION/g" "../$VELERO_VERSION/install.sh.tmpl"
    sed -i "s/__GCP_PLUGIN_VERSION__/$GCP_PLUGIN_VERSION/g" "../$VELERO_VERSION/install.sh.tmpl"
    mv "../$VELERO_VERSION/install.sh.tmpl" "../$VELERO_VERSION/install.sh"
}

function add_as_latest() {
    sed -i "/cron-velero-update/a\    \"${VELERO_VERSION}\"\," ../../../web/src/installers/versions.js
}

VELERO_VERSION=""
AWS_PLUGIN_VERSION=""
AZURE_PLUGIN_VERSION=""
GCP_PLUGIN_VERSION=""
function main() {
    get_latest_release_version VELERO_VERSION https://github.com/vmware-tanzu/velero/releases/latest 

    get_latest_release_version AWS_PLUGIN_VERSION https://github.com/vmware-tanzu/velero-plugin-for-aws/releases/latest 
    get_latest_release_version AZURE_PLUGIN_VERSION https://github.com/vmware-tanzu/velero-plugin-for-microsoft-azure/releases/latest 
    get_latest_release_version GCP_PLUGIN_VERSION https://github.com/vmware-tanzu/velero-plugin-for-gcp/releases/latest 

    if [ -d "../${VELERO_VERSION}" ]; then
        exit 0
    fi

    generate

    add_as_latest

    echo "::set-output name=velero_version::$VELERO_VERSION"
}

main "$@"
