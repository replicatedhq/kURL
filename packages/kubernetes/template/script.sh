#!/bin/bash

set -euo pipefail

# list_supported_minors: the minor set comes from the Dockerfile.1<minor> files (see add-minor.sh)
# shellcheck source=packages/kubernetes/template/minors.sh
. "$(dirname "${BASH_SOURCE[0]}")/minors.sh"

# versions_js_path prints the path of web/src/installers/versions.js relative to the template dir.
# KURL_VERSIONS_JS overrides it (used by tests).
function versions_js_path() {
    echo "${KURL_VERSIONS_JS:-../../../web/src/installers/versions.js}"
}

# versions_js_kubernetes_section prints the kubernetes array of versions.js ($1).
function versions_js_kubernetes_section() {
    sed -n '/^[[:space:]]*kubernetes: \[/,/^[[:space:]]*\],/p' "$1"
}

# minor_in_versions_js succeeds when the kubernetes array of versions.js ($2) lists a 1.<minor>.x version.
function minor_in_versions_js() {
    versions_js_kubernetes_section "$2" | grep -Eq "\"1\.${1}\.[0-9]+\""
}

# Populate VERSIONS array with the latest patch of every kURL-supported minor (one per Dockerfile.1<minor>).
# Minors not yet listed in versions.js (scaffolded by add-minor.sh) are skipped: the first patch of a new
# minor is added by the add-kubernetes-minor skill (script.sh 1.N.P), not by the patch cron.
VERSIONS=()
function find_available_versions() {
    local versions_js=
    versions_js="$(versions_js_path)"
    if [ ! -f "$versions_js" ]; then
        echo "versions.js not found at $versions_js" >&2
        return 1
    fi
    # "minor not listed" below must mean exactly that, not that versions.js changed shape and the
    # kubernetes array was not found
    if ! versions_js_kubernetes_section "$versions_js" | grep -Eq '"1\.[0-9]+\.[0-9]+"'; then
        echo "ERROR: no kubernetes versions found in the kubernetes array of $versions_js" >&2
        return 1
    fi
    local minors=()
    mapfile -t minors < <(list_supported_minors .)
    if [ ${#minors[@]} -eq 0 ]; then
        echo "No Dockerfile.1<minor> files found in $(pwd)" >&2
        return 1
    fi

    local minor=
    for minor in "${minors[@]}"; do
        if ! minor_in_versions_js "$minor" "$versions_js"; then
            echo "Kubernetes 1.${minor} is not listed in versions.js yet, skipping (added by the add-kubernetes-minor skill)"
            continue
        fi
        # A minor listed in versions.js must resolve to a version: a failed build or an empty or failed
        # package listing is an error, not a silent skip that would leave the minor without patch updates.
        if ! docker build -t "k8s1${minor}" - < "Dockerfile.1${minor}"; then
            echo "ERROR: building the Kubernetes 1.${minor} package image failed (Dockerfile.1${minor})" >&2
            return 1
        fi
        local apt_list=
        local apt_err=
        local rc=0
        apt_err="$(mktemp)"
        apt_list="$(docker run --rm "k8s1${minor}" apt list -a kubelet 2>"$apt_err")" || rc=$?
        if [ "$rc" -ne 0 ]; then
            echo "ERROR: listing kubelet versions for Kubernetes 1.${minor} failed (docker run k8s1${minor}, exit $rc):" >&2
            tail -n 20 "$apt_err" >&2
            rm -f "$apt_err"
            return 1
        fi
        rm -f "$apt_err"
        local versions=()
        mapfile -t versions < <(printf '%s\n' "$apt_list" | grep -Eo "1\.${minor}\.[0-9]+" | sort -rV | uniq)
        if [ ${#versions[@]} -eq 0 ]; then
            echo "ERROR: no kubelet 1.${minor}.x versions found in the Kubernetes 1.${minor} package repository" >&2
            return 1
        fi
        echo "Found latest version for Kubernetes 1.${minor}: ${versions[0]}"
        VERSIONS+=("${versions[0]}")
    done

    echo "Found ${#VERSIONS[*]} versions for Kubernetes: ${VERSIONS[*]:-}"
}

# github_curl GETs a GitHub API URL. It only sends the Authorization header when GITHUB_TOKEN is
# set and non-empty (unauthenticated calls work, with a lower rate limit). The header is passed on
# stdin so the token never shows up in the process list, and redirects are not followed so the
# header is never sent anywhere else. Fails (non-zero) on HTTP errors such as rate limiting.
# Retries once after KURL_GITHUB_RETRY_DELAY seconds (default 3). Each attempt's body goes to a temp
# file and only a successful attempt's body is printed, so a failed attempt never leaks partial output.
function github_curl() {
    local rc=0
    local attempt=
    local body=
    body="$(mktemp)"
    for attempt in 1 2; do
        rc=0
        if [ -n "${GITHUB_TOKEN:-}" ]; then
            printf 'Authorization: token %s\n' "$GITHUB_TOKEN" | curl -fsS --proto '=https' --connect-timeout 10 --max-time 60 -H @- "$@" > "$body" || rc=$?
        else
            curl -fsS --proto '=https' --connect-timeout 10 --max-time 60 "$@" < /dev/null > "$body" || rc=$?
        fi
        if [ "$rc" -eq 0 ]; then
            cat "$body"
            rm -f "$body"
            return 0
        fi
        if [ "$attempt" -eq 1 ]; then
            echo "WARNING: GitHub API request failed (curl exit $rc), retrying: $*" >&2
            sleep "${KURL_GITHUB_RETRY_DELAY:-3}"
        fi
    done
    rm -f "$body"
    echo "ERROR: GitHub API request failed (curl exit $rc): $*. If this is rate limiting, set GITHUB_TOKEN or retry later." >&2
    return "$rc"
}

# sha256_of prints the sha256 hex digest of a file
function sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{ print $1 }'
    else
        shasum -a 256 "$1" | awk '{ print $1 }'
    fi
}

# download_kubeadm downloads the linux/amd64 kubeadm binary for a version into a directory and
# verifies it against the published sha256 before making it executable.
function download_kubeadm() {
    local version="$1"
    local dir="$2"
    local url="https://dl.k8s.io/release/v${version}/bin/linux/amd64/kubeadm"

    local rc=0
    curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 600 -o "$dir/kubeadm" "$url" || rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "ERROR: failed to download kubeadm v${version} from ${url} (curl exit $rc)" >&2
        rm -f "$dir/kubeadm"
        return 1
    fi

    # a failed fetch is a transport error, reported as such; only a fetched file that isn't a
    # sha256 is an invalid published checksum
    local checksum=
    checksum="$(curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 60 "${url}.sha256")" || rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "ERROR: failed to fetch the kubeadm v${version} checksum from ${url}.sha256 (curl exit $rc)" >&2
        rm -f "$dir/kubeadm"
        return 1
    fi
    local expected=
    expected="$(printf '%s\n' "$checksum" | awk '{ print $1; exit }')"
    if ! [[ "$expected" =~ ^[0-9a-f]{64}$ ]]; then
        echo "ERROR: invalid sha256 published for kubeadm v${version}: '${expected}'" >&2
        rm -f "$dir/kubeadm"
        return 1
    fi
    local actual=
    actual="$(sha256_of "$dir/kubeadm")"
    if [ "$actual" != "$expected" ]; then
        echo "ERROR: kubeadm v${version} sha256 mismatch: expected ${expected}, got ${actual}" >&2
        rm -f "$dir/kubeadm"
        return 1
    fi
    chmod +x "$dir/kubeadm"
}

# use_securebuild_images rewrites upstream images to SecureBuild ones in a Manifest (default
# ../<version>/Manifest) and copies the override files into ../<version>/, when ./securebuild-<version> exists.
function use_securebuild_images() {
    local version="$1"
    local manifest="${2:-../$version/Manifest}"
    local securebuild_dir="./securebuild-${version}"
    [ -d "$securebuild_dir" ] || return 0

    local name= image= upstream_image=
    while read -r name image upstream_image; do
        sed -i "s|$upstream_image|$image|" "$manifest"
    done < "$securebuild_dir/kubeadm-image-overrides"

    local workload= container=
    while read -r workload container image upstream_image; do
        sed -i "s|$upstream_image|$image|" "$manifest"
    done < "$securebuild_dir/image-overrides"

    cp -r "$securebuild_dir"/* "../$version/"
}

# generate_version_directory writes ../<version>/Manifest. It runs in a subshell so the EXIT trap
# cleans up its temp files. The Manifest is built in a temp dir, copied to a temp file next to its
# destination and renamed into place, so ../<version>/Manifest is never left partially written.
function generate_version_directory() (
    local version="$1"
    # not local: the EXIT trap runs after the function body (this subshell keeps them contained)
    workdir="$(mktemp -d)"
    staged=
    trap 'rm -rf "$workdir"; [ -z "$staged" ] || rm -f "$staged"' EXIT

    download_kubeadm "$version" "$workdir" || return 1

    # capture first so a kubeadm failure fails the script. The sha256 check above only catches
    # corruption (the checksum comes from the same origin), so kubeadm runs with an empty
    # environment: no tokens or credentials, and HOME is the temp dir (no ~/.config, ~/.docker, ...).
    local images=
    local rc=0
    images="$(env -i PATH="$PATH" HOME="$workdir" "$workdir/kubeadm" config images list --kubernetes-version="${version}")" || rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "ERROR: kubeadm config images list failed for ${version} (exit $rc)" >&2
        return 1
    fi
    if [ -z "$images" ]; then
        echo "ERROR: kubeadm config images list returned no images for ${version}" >&2
        return 1
    fi

    local manifest="$workdir/Manifest"
    : > "$manifest"
    local image=
    local name=
    while read -r image; do
        [ -n "$image" ] || continue
        # registry.k8s.io/kube-apiserver:v1.20.2 -> kube-apiserver
        name="$(echo "$image" | awk -F':' '{ print $1 }' | awk -F '/' '{ print $2 }')"
        if [ -z "$name" ]; then
            echo "ERROR: could not derive an image name from '${image}'" >&2
            return 1
        fi
        echo "image ${name} ${image}" >> "$manifest"
    done <<< "$images"

    local minor=
    minor="$(echo "$version" | awk -F'.' '{ print $2 }')"
    local releases=
    releases="$(github_curl https://api.github.com/repos/kubernetes-sigs/cri-tools/releases)" || return 1
    local criToolsVersion=
    criToolsVersion="$(echo "$releases" | grep '"tag_name": ' | { grep -Eo "1\.${minor}\.[0-9]+" || true; } | head -1)"

    # Fallback: Kubernetes 1.23 doesn't have a version of criTools as of 2021-12-13
    # Any latest version of criTools will work for any version of Kubernetes >=1.16, so this is a safe operation
    if [ -z "$criToolsVersion" ]; then
        criToolsVersion="$(echo "$releases" | grep '"tag_name": ' | { grep -Eo "1\.[2-9][0-9]\.[0-9]+" || true; } | head -1)"
    fi
    if ! [[ "$criToolsVersion" =~ ^1\.[0-9]+\.[0-9]+$ ]]; then
        echo "ERROR: could not determine a cri-tools version for Kubernetes ${version}" >&2
        return 1
    fi

    {
        echo ""
        echo "asset kubeadm https://dl.k8s.io/v$version/bin/linux/amd64/kubeadm"
        echo "asset crictl-linux-amd64.tar.gz https://github.com/kubernetes-sigs/cri-tools/releases/download/v$criToolsVersion/crictl-v$criToolsVersion-linux-amd64.tar.gz"
        echo ""
        echo "asset kustomize-v5.4.3.tar.gz https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.4.3/kustomize_v5.4.3_linux_amd64.tar.gz"
    } >> "$manifest"

    mkdir -p "../$version"
    use_securebuild_images "$version" "$manifest"
    staged="$(mktemp "../$version/.Manifest.XXXXXX")"
    cat "$manifest" > "$staged"
    # mktemp creates 0600; the Manifest ships in the dist tarball, so keep the usual 0644
    chmod 644 "$staged"
    mv "$staged" "../$version/Manifest"
    staged=
)

# generate_conformance_package writes ../<version>/conformance/Manifest, only once complete.
function generate_conformance_package() {
    local version="$1"

    # --mode quick image
    local images=
    local rc=0
    images="$(docker run --rm --entrypoint e2e.test "registry.k8s.io/conformance:v${version}" --list-images)" || rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "ERROR: listing conformance images failed (docker run registry.k8s.io/conformance:v${version}, exit $rc)" >&2
        return 1
    fi
    local image=
    image="$(echo "$images" | { grep "nginx" || true; } | sort -n | head -n 1)"
    if [ -z "$image" ]; then
        echo "ERROR: no nginx image found in registry.k8s.io/conformance:v${version} --list-images" >&2
        return 1
    fi
    local name=
    name="$(echo "$image" | awk -F'[/:]' '{ i = 2; for (--i; i >= 0; i--){ printf "%s-",$(NF-i)} print "" }' | sed 's/\./-/' | sed 's/-$//')"
    if [ -z "$name" ]; then
        echo "ERROR: could not derive an image name from '${image}'" >&2
        return 1
    fi

    mkdir -p "../$version/conformance"
    local tmp=
    tmp="$(mktemp "../$version/conformance/.Manifest.XXXXXX")"
    # add conformance image for sonobuoy to manifest
    {
        echo "image conformance registry.k8s.io/conformance:v${version}"
        echo "image $name $image"
    } > "$tmp"
    chmod 644 "$tmp"
    mv "$tmp" "../$version/conformance/Manifest"

    # The following code would add all conformance images to the manifest but it adds too much to the bundle:
    # sonobuoy_pull_images "$version" || true
    # for image in $(docker run --rm --entrypoint e2e.test "registry.k8s.io/conformance:v${version}" --list-images) ; do
    #     if docker inspect "$image" >/dev/null 2>&1 ; then
    #         echo "image <name> $image" >> "../$version/conformance/Manifest"
    #     fi
    # done
}

function sonobuoy_pull_images() {
    local version="$1"
    local tmpdir="$(mktemp -d)"
    download_sonobuoy "$tmpdir"

    "${tmpdir}/sonobuoy" images pull --kubernetes-version "v${version}"
}

function download_sonobuoy() {
    local tmpdir="$1"
    local sonobuoy_version="$(get_latest_sonobuoy_release_version)"
    curl -sL -o "${tmpdir}/sonobuoy.tar.gz" https://github.com/vmware-tanzu/sonobuoy/releases/download/v${sonobuoy_version}/sonobuoy_${sonobuoy_version}_linux_amd64.tar.gz && \
        tar xzf "${tmpdir}/sonobuoy.tar.gz" -C "${tmpdir}"
}

function get_latest_sonobuoy_release_version() {
    curl -sI https://github.com/vmware-tanzu/sonobuoy/releases/latest | \
        grep -i "^location" | \
        grep -Eo "0\.[0-9]+\.[0-9]+"
}

# versions_minors prints the distinct minors of the VERSIONS entries (1.37.2 -> 37)
function versions_minors() {
    printf '%s\n' ${VERSIONS[@]+"${VERSIONS[@]}"} | awk -F. 'NF == 3 { print $2 }' | sort -rn | uniq
}

# check_versions_js_markers fails unless versions.js has exactly one
# "// cron-kubernetes-update-1<minor>" marker for the minor of every VERSIONS entry, so a version is
# never generated without a place to list it (run add-minor.sh <minor> first for a new minor).
function check_versions_js_markers() {
    local versions_js=
    versions_js="$(versions_js_path)"
    local minor=
    local count=
    for minor in $(versions_minors); do
        count="$(grep -Ec "^[[:space:]]*// cron-kubernetes-update-1${minor}[[:space:]]*\$" "$versions_js" || true)"
        if [ "$count" != "1" ]; then
            echo "ERROR: expected one '// cron-kubernetes-update-1${minor}' marker in ${versions_js}, found ${count}. For a new minor run add-minor.sh ${minor} first." >&2
            return 1
        fi
    done
}

# update_available_versions adds the newest VERSIONS entry of every minor right below its
# "// cron-kubernetes-update-1<minor>" marker in versions.js, unless already listed there.
function update_available_versions() {
    local versions_js=
    versions_js="$(versions_js_path)"
    check_versions_js_markers || return 1
    local minor=
    local latest=
    local listed=
    for minor in $(versions_minors); do
        latest="$(printf '%s\n' ${VERSIONS[@]+"${VERSIONS[@]}"} | grep "^1\.${minor}\." | sort -rV | head -n 1)"
        # everything after the marker up to the end of the kubernetes array
        listed="$(sed "0,/cron-kubernetes-update-1${minor}\b/d" "$versions_js" | sed '/\],/,$d')"
        if ! grep -qF "\"${latest}\"" <<< "$listed" ; then
            sed -i "/cron-kubernetes-update-1${minor}\b/a\    \"${latest}\"\," "$versions_js"
            grep -qF "\"${latest}\"," "$versions_js" || { echo "ERROR: failed to add ${latest} to ${versions_js}" >&2; return 1; }
        fi
    done
}

function generate_step_versions() {
    local steps=()
    local version=
    local max_minor=0
    while read -r version; do
        if ! echo "$version" | grep -Eq '[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+' ; then
            continue
        fi
        local step_minor=
        step_minor="$(echo "$version" | cut -d. -f2)"
        steps[$step_minor]="$version"
        ((step_minor > max_minor)) && max_minor="$step_minor"
    done <<< "$(find ../ -maxdepth 1 -type d -printf '%P\n' | sort -V)"
    for (( version=0; version <= max_minor; version++ )); do
        [ "${steps[version]+abc}" ] && continue
        steps[$version]="0.0.0"
    done

    sed -i 's|^STEP_VERSIONS=(.*|STEP_VERSIONS=('"${steps[*]}"')|' ../../../hack/testdata/manifest/clean
    sed -i 's|^STEP_VERSIONS=(.*|STEP_VERSIONS=('"${steps[*]}"')|' ../../../scripts/Manifest
}

function main() {
    # relative ../ paths below are relative to the template dir, whatever the caller's cwd
    cd "${KURL_TEMPLATE_DIR:-$(dirname "${BASH_SOURCE[0]}")}"

    VERSIONS=("$@")
    if [ ${#VERSIONS[@]} -eq 0 ]; then
        find_available_versions
    fi
    check_versions_js_markers

    local version=
    for version in ${VERSIONS[@]+"${VERSIONS[@]}"}; do
        generate_version_directory "${version}"
        generate_conformance_package "${version}"
    done
    echo "kubernetes_version=${VERSIONS[*]:-}" >> "${GITHUB_OUTPUT:-/dev/null}"

    update_available_versions

    generate_step_versions
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
