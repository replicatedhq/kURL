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
    local base="$1"

    for dir in $(find "${base}" -mindepth 2 -maxdepth 2 -type d)
    do
        local name=$(echo $dir | awk -F "/" '{print $2 }')
        local version=$(echo $dir | awk -F "/" '{print $3 }')
        if [ "$version" = "template" ] || [ "$version" = "build-images" ]; then
            continue
        fi
        echo "${name}-${version}.tar.gz ${dir}/"
        if [ "${name}" = "kubernetes" ]; then
            local minor="$(echo "${version}" | sed -E 's/^v?[0-9]+\.([0-9]+).[0-9]+.*$/\1/')"
            if [ "${minor}" -ge 17 ]; then
                local conformance_version="$(echo "${version}" | sed -E 's/^v?([0-9]+\.[0-9]+.[0-9]+).*$/\1/')"
                echo "kubernetes-conformance-${conformance_version}.tar.gz ${base}/kubernetes/${conformance_version}/"
            fi
        fi
    done
}

function list_all_addons() {
    pkgs addons | sort
}

function list_all_packages() {
    pkgs packages | sort | uniq
}

function list_other() {
    echo "install.tmpl"
    echo "join.tmpl"
    echo "upgrade.tmpl"
    echo "tasks.tmpl"
    echo "common.tar.gz"
    echo "$KURL_BIN_UTILS_FILE"
    if [ -n "$KURL_BIN_UTILS_FILE_LATEST" ]; then
        echo "$KURL_BIN_UTILS_FILE_LATEST"
    fi
}

function list_go_bins() {
    echo "common.tar.gz"
    echo "$KURL_BIN_UTILS_FILE"
    if [ -n "$KURL_BIN_UTILS_FILE_LATEST" ]; then
        echo "$KURL_BIN_UTILS_FILE_LATEST"
    fi
}

function list_all() {
    list_other
    list_all_addons
    list_all_packages
}

# change_detection_paths echoes, one per line, the repository paths whose changes
# must force a rebuild of the package identified by key. It is the single source
# for that decision, shared by the staging and versioned upload scripts so the two
# never drift.
#
# kubernetes host packages (kubelet/kubectl/kubeadm .debs and .rpms) are built
# from the per-OS bundle Dockerfiles in bundles/ (e.g. bundles/k8s-ubuntu2604),
# not from anything under packages/kubernetes/<version>/. The set of supported
# OSes is driven by the single-source os-matrix.yaml (replicatedhq/kURL#6081),
# which regenerates those bundle Dockerfiles and the build Makefile. So adding a
# supported OS touches os-matrix.yaml and bundles/ but nothing under
# packages/kubernetes/<version>/ -- and unless both are watched here the
# kubernetes tarball is never rebuilt, leaving the new OS with no host packages
# ("kubelet: command not found"). Watch os-matrix.yaml (the authoritative source)
# and bundles/ for kubernetes packages; every package always watches its own path.
#
# The match is kubernetes-[0-9] (e.g. kubernetes-1.35.7), NOT a bare
# "kubernetes-" substring, so it excludes kubernetes-conformance-<ver>. Conformance
# archives are built from packages/kubernetes/<ver>/conformance/Manifest (sonobuoy
# images) and depend on neither bundles/ nor os-matrix.yaml, so a change to those
# must not needlessly rebuild and re-ship every conformance archive.
function change_detection_paths() {
    local key="$1"
    local base_path="$2"
    echo "${base_path}"
    if echo "${key}" | grep -qE "kubernetes-[0-9]" ; then
        echo "bundles/"
        echo "os-matrix.yaml"
    fi
}
