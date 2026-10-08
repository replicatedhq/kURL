#!/bin/bash

# Guards every containerd add-on version against the one-off fix that only patched
# addons/containerd/1.7.29 for Kubernetes 1.37's kubeadm.k8s.io/v1beta4 config API
# (see addons/containerd/template/base/install.sh). A containerd version whose
# directory ships a kubeadm-*-config-v1beta4.yaml sibling must also select it from
# install.sh, or pairing that containerd version with Kubernetes 1.37+ fails with
# "wrong node kind: expected SequenceNode but got MappingNode" when kubeadm parses
# the v1beta2-shaped (map) patch as v1beta4 (list).

set -e

function test_every_v1beta4_yaml_sibling_is_selected_by_install_sh() {
    local failures=()
    local dir version install_sh

    for dir in addons/containerd/*/; do
        version="$(basename "$dir")"
        [ "$version" = "template" ] && continue
        install_sh="${dir}install.sh"

        if [ -f "${dir}kubeadm-init-config-v1beta4.yaml" ]; then
            if ! grep -q 'kubeadm-init-config-v1beta4.yaml' "$install_sh" 2>/dev/null; then
                failures+=("$version: kubeadm-init-config-v1beta4.yaml present but not referenced in install.sh")
            fi
        fi

        if [ -f "${dir}kubeadm-join-config-v1beta4.yaml" ]; then
            if ! grep -q 'kubeadm-join-config-v1beta4.yaml' "$install_sh" 2>/dev/null; then
                failures+=("$version: kubeadm-join-config-v1beta4.yaml present but not referenced in install.sh")
            fi
        fi
    done

    if [ "${#failures[@]}" -ne 0 ]; then
        printf '%s\n' "${failures[@]}"
    fi
    assertEquals 0 "${#failures[@]}"
}

# containerd_version_lt_2_0_0 reports whether $1 is a containerd version older than
# 2.0.0. Kubernetes 1.37+ dropped upstream support for containerd 1.x (matching
# containerd's own CRI v1alpha2 removal), so kURL only pairs Kubernetes 1.37+ with
# containerd 2.x. containerd 1.x versions (including 1.6.x/1.7.x) never need the
# v1beta4 kubeadm config patch siblings.
function containerd_version_lt_2_0_0() {
    local major="${1%%.*}"

    if [ "$major" -lt 2 ]; then
        return 0
    fi
    return 1
}

# every version still offered in web/src/installers/versions.js that has a kustomize
# patch mechanism (i.e. not the pre-kustomize 1.2.13) and that can actually be paired
# with Kubernetes 1.37+ (i.e. containerd 2.x, see containerd_version_lt_2_0_0 above)
# must carry the v1beta4 sibling files, so pairing it with Kubernetes 1.37+ does not
# silently fall back to the broken v1beta2 shape.
function test_every_selectable_version_with_kustomize_patches_has_v1beta4_siblings() {
    local failures=()
    local dir version

    for dir in addons/containerd/*/; do
        version="$(basename "$dir")"
        [ "$version" = "template" ] && continue
        [ "$version" = "1.2.13" ] && continue # predates the kustomize kubeadm patch mechanism entirely
        containerd_version_lt_2_0_0 "$version" && continue # Kubernetes 1.37+ only pairs with containerd 2.x

        if ! grep -q "\"$version\"" web/src/installers/versions.js; then
            continue # not selectable from the web installer
        fi

        if [ ! -f "${dir}kubeadm-init-config-v1beta4.yaml" ]; then
            failures+=("$version: missing kubeadm-init-config-v1beta4.yaml")
        fi
        if [ ! -f "${dir}kubeadm-join-config-v1beta4.yaml" ]; then
            failures+=("$version: missing kubeadm-join-config-v1beta4.yaml")
        fi
    done

    if [ "${#failures[@]}" -ne 0 ]; then
        printf '%s\n' "${failures[@]}"
    fi
    assertEquals 0 "${#failures[@]}"
}

# a containerd version below 2.0.0 can never be paired with Kubernetes 1.37+ (see
# containerd_version_lt_2_0_0 above), so it must not carry the v1beta4 kubeadm config
# patch siblings; this guards against the backfill regressing back onto 1.x versions.
function test_no_sub_2_0_0_version_has_v1beta4_siblings() {
    local failures=()
    local dir version

    for dir in addons/containerd/*/; do
        version="$(basename "$dir")"
        [ "$version" = "template" ] && continue
        ! containerd_version_lt_2_0_0 "$version" && continue # containerd 2.x is expected to carry siblings

        if [ -f "${dir}kubeadm-init-config-v1beta4.yaml" ]; then
            failures+=("$version: kubeadm-init-config-v1beta4.yaml present but containerd <2.0.0 never pairs with Kubernetes 1.37+")
        fi
        if [ -f "${dir}kubeadm-join-config-v1beta4.yaml" ]; then
            failures+=("$version: kubeadm-join-config-v1beta4.yaml present but containerd <2.0.0 never pairs with Kubernetes 1.37+")
        fi
    done

    if [ "${#failures[@]}" -ne 0 ]; then
        printf '%s\n' "${failures[@]}"
    fi
    assertEquals 0 "${#failures[@]}"
}

# shellcheck disable=SC1091
. shunit2
