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

# every version still offered in web/src/installers/versions.js that has a kustomize
# patch mechanism (i.e. not the pre-kustomize 1.2.13) must carry the v1beta4 sibling
# files, so pairing it with Kubernetes 1.37+ does not silently fall back to the
# broken v1beta2 shape.
function test_every_selectable_version_with_kustomize_patches_has_v1beta4_siblings() {
    local failures=()
    local dir version

    for dir in addons/containerd/*/; do
        version="$(basename "$dir")"
        [ "$version" = "template" ] && continue
        [ "$version" = "1.2.13" ] && continue # predates the kustomize kubeadm patch mechanism entirely

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

# shellcheck disable=SC1091
. shunit2
