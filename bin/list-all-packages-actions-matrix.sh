#!/bin/bash

set -eo pipefail

# shellcheck source=list-all-packages.sh
source ./bin/list-all-packages.sh

function require() {
    if [ -z "$2" ]; then
        echo "validation failed: $1 unset"
        exit 1
    fi
}

require KURL_UTIL_IMAGE "${KURL_UTIL_IMAGE}" # required for common package
require KURL_BIN_UTILS_FILE "${KURL_BIN_UTILS_FILE}"

batch_size=3

i=0
start=0

package_list=$(list_all | awk '{print $1}')
if [ "${FILTER_GO_BINS_ONLY}" == "1" ]; then
    package_list=$(list_go_bins| awk '{print $1}')
fi

printf '{"include": ['
for package in $package_list
do
    if [ "${i}" = "0" ]; then
        if [ "${start}" = "1" ]; then
            printf '"},'
        fi
        printf '{"batch": "'
        start=1
    fi
    printf '%s ' "${package}"
    i="$((i+1))"
    if [ "${i}" = "${batch_size}" ]; then
        i=0
    fi
done
printf '"}'
printf ']}'
