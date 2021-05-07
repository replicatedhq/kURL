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

comma=""
printf '{"include": ['
for package in $(list_all | awk '{print $1}')
do
    printf '%s{"package": "%s"}' "${comma}" "${package}"
    comma=","
done
printf ']}'
