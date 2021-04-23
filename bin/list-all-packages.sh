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
        if [ "$version" = "template" ] || [ "$version" = "build-images" ]; then
            continue
        fi
        # HACK: allow for conformance packages to be built for rke2 and k3s for versions we do not support of kubeadm.
        if [ -f "$dir/Manifest" ]; then
            echo "${name}-${version}.tar.gz ${dir}/${name}/${version}/"
        fi
        if [ "${name}" = "kubernetes" ] || [ "${name}" = "k-3-s" ] || [ "${name}" = "rke-2" ]; then
            local minor="$(echo "${version}" | sed -E 's/^v?[0-9]+\.([0-9]+).[0-9]+.*$/\1/')"
            if [ "${minor}" -ge 17 ]; then
                local conformance_version="$(echo "${version}" | sed -E 's/^v?([0-9]+\.[0-9]+.[0-9]+).*$/\1/')"
                echo "kubernetes-conformance-${conformance_version}.tar.gz ${dir}/kubernetes/${conformance_version}/"
            fi
        fi
    done
}

function list_all_addons() {
    pkgs addons
}

function list_all_packages() {
    pkgs packages | sort | uniq
}

function list_other() {
    echo "docker-18.09.8.tar.gz bundles/"
    echo "docker-19.03.4.tar.gz bundles/"
    echo "docker-19.03.10.tar.gz bundles/"
    echo "docker-20.10.5.tar.gz bundles/"
    echo "common.tar.gz"
    echo "$KURL_BIN_UTILS_FILE"
}

function list_all() {
    list_all_addons
    list_all_packages
    list_other
}
