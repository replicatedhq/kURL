#!/bin/bash

set -euo pipefail

function log() {
    echo "$1" 1>&2
}

function bail() {
    log "$1"
    exit 1
}          

function main() {
    VERSION_TAG=$1
    tag_arr=(${VERSION_TAG//-/ })
    todays_date=$(date +'v%Y.%m.%d')
    if [ "${todays_date}" != "${tag_arr[0]}" ]; then
        bail "Tag must have today's date suffixed with a running number, <vYYYY.MM.DD-[0..n]>"
    fi
}

main "$@"
