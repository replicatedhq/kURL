#!/bin/bash

function require() {
    if [ -z "$2" ]; then
        echo "validation failed: $1 unset"
        exit 1
    fi
}

require KURL_UTIL_IMAGE "${KURL_UTIL_IMAGE}" # required for common package
require KURL_BIN_UTILS_FILE "${KURL_BIN_UTILS_FILE}"

function pkgs() {
    for dir in $(find $1 -mindepth 2 -maxdepth 2 -type d)
    do
        local name=$(echo $dir | awk -F "/" '{print $2 }')
        local version=$(echo $dir | awk -F "/" '{print $3 }')
        echo "${name}-${version}.tar.gz"
    done
}

function list_all_packages() {
    pkgs addons
    pkgs packages
    echo "docker-18.09.8.tar.gz"
    echo "docker-19.03.4.tar.gz"
    echo "docker-19.03.10.tar.gz"
    echo "common.tar.gz"
    echo "containerd-1.2.13.tar.gz"
    echo "$KURL_BIN_UTILS_FILE"
}

list_all_packages
