#!/bin/bash

set -eo pipefail

function require() {
    if [ -z "$2" ]; then
        echo "validation failed: $1 unset"
        exit 1
    fi
}

batch_size=4
i=0
start=0

package_list=
if [ "${LIST_FROM_STAGE_S3}" == "1" ]; then
    package_list=$(./bin/list-packages-s3.sh | awk '{print $1}')
else
    require KURL_UTIL_IMAGE "${KURL_UTIL_IMAGE}" # required for common package
    require KURL_BIN_UTILS_FILE "${KURL_BIN_UTILS_FILE}"
    # shellcheck source=list-all-packages.sh
    source ./bin/list-all-packages.sh
    if [ "${FILTER_GO_BINS_ONLY}" == "1" ]; then
        package_list=$(list_go_bins| awk '{print $1}')
    else
        # default to listing all packages
        package_list=$(list_all | awk '{print $1}')
    fi
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
