#!/bin/bash

# Tests for change_detection_paths() in list-all-packages.sh -- the single source
# deciding which repository paths force a package rebuild in the upload scripts.
#
# Guards the DRY promise of replicatedhq/kURL#6081: adding a supported OS is a
# single edit to os-matrix.yaml (which regenerates the bundle Dockerfiles), so
# os-matrix.yaml MUST be watched for kubernetes packages. Otherwise the diff of
# packages/kubernetes/<version>/ is empty, the kubernetes tarball never rebuilds,
# and the new OS ships with no host packages ("kubelet: command not found").

# list-all-packages.sh calls require on these at source time.
export KURL_UTIL_IMAGE="test"
export KURL_BIN_UTILS_FILE="test"

# shellcheck source=list-all-packages.sh
. ./bin/list-all-packages.sh

assertPathWatched() {
    echo "$2" | grep -qx "$3"
    assertEquals "$1" "0" "$?"
}

assertPathNotWatched() {
    echo "$2" | grep -qx "$3"
    assertNotEquals "$1" "0" "$?"
}

testKubernetesWatchesOwnPathBundlesAndOsMatrix() {
    local paths
    paths="$(change_detection_paths "kubernetes-1.29.1.tar.gz" "packages/kubernetes/1.29.1/")"
    assertPathWatched "kubernetes must watch its own path" "${paths}" "packages/kubernetes/1.29.1/"
    assertPathWatched "kubernetes must watch bundles/ (host packages built there)" "${paths}" "bundles/"
    assertPathWatched "kubernetes must watch os-matrix.yaml (DRY single source)" "${paths}" "os-matrix.yaml"
}

testConformanceKubernetesWatchesOsMatrix() {
    local paths
    paths="$(change_detection_paths "kubernetes-conformance-1.29.1.tar.gz" "packages/kubernetes/1.29.1/")"
    assertPathWatched "conformance kubernetes must watch os-matrix.yaml" "${paths}" "os-matrix.yaml"
}

testNonKubernetesWatchesOnlyOwnPath() {
    local paths
    paths="$(change_detection_paths "containerd-1.6.4.tar.gz" "packages/containerd/1.6.4/")"
    assertPathWatched "non-kubernetes must watch its own path" "${paths}" "packages/containerd/1.6.4/"
    assertPathNotWatched "non-kubernetes must NOT watch os-matrix.yaml" "${paths}" "os-matrix.yaml"
    assertPathNotWatched "non-kubernetes must NOT watch bundles/" "${paths}" "bundles/"
}

# End-to-end: prove that an os-matrix.yaml change flips the exact git-diff that
# package_has_changes() runs, for a kubernetes package, from "no changes" to
# "changes" -- and that the identical change is invisible to a non-kubernetes
# package (so we do not over-rebuild).
testOsMatrixChangeFlipsGitDiffForKubernetes() {
    if ! command -v git >/dev/null 2>&1 ; then
        startSkipping
        return 0
    fi

    # git -C keeps every command scoped to the temp repo, so assertions run in
    # this (shunit2) shell rather than a subshell where failures would be lost.
    local repo
    repo="$(mktemp -d)"
    mkdir -p "${repo}/packages/kubernetes/1.29.1" "${repo}/packages/containerd/1.6.4" "${repo}/bundles"
    echo "FROM scratch" > "${repo}/bundles/k8s-ubuntu2604.Dockerfile"
    echo "content" > "${repo}/packages/kubernetes/1.29.1/Deps"
    echo "content" > "${repo}/packages/containerd/1.6.4/Deps"
    printf 'oses:\n  - id: ubuntu-2404\n' > "${repo}/os-matrix.yaml"
    git -C "${repo}" init -q
    git -C "${repo}" config user.email "test@example.com"
    git -C "${repo}" config user.name "test"
    git -C "${repo}" add -A
    git -C "${repo}" commit -qm base
    local base
    base="$(git -C "${repo}" rev-parse HEAD)"

    # Change ONLY os-matrix.yaml -- the single-source "add an OS" edit.
    printf 'oses:\n  - id: ubuntu-2404\n  - id: ubuntu-2604\n' > "${repo}/os-matrix.yaml"
    git -C "${repo}" add -A
    git -C "${repo}" commit -qm add-os
    local head
    head="$(git -C "${repo}" rev-parse HEAD)"

    # kubernetes package: os-matrix.yaml is watched, so the diff is non-empty.
    # This mirrors package_has_changes()'s exact git-diff invocation.
    local kpaths=()
    while IFS= read -r p; do kpaths+=( "${p}" ); done \
        < <(change_detection_paths "kubernetes-1.29.1.tar.gz" "packages/kubernetes/1.29.1/")
    git -C "${repo}" diff --quiet "${base}" -- "${kpaths[@]}" "${head}" -- "${kpaths[@]}"
    assertNotEquals "os-matrix.yaml change must register as changes for kubernetes" "0" "$?"

    # non-kubernetes package: os-matrix.yaml is NOT watched, diff stays empty.
    local cpaths=()
    while IFS= read -r p; do cpaths+=( "${p}" ); done \
        < <(change_detection_paths "containerd-1.6.4.tar.gz" "packages/containerd/1.6.4/")
    git -C "${repo}" diff --quiet "${base}" -- "${cpaths[@]}" "${head}" -- "${cpaths[@]}"
    assertEquals "os-matrix.yaml change must be invisible to containerd" "0" "$?"

    rm -rf "${repo}"
}

# shellcheck source=/dev/null
. shunit2
