#!/bin/bash

set -euo pipefail

# list_supported_minors prints the Kubernetes minors kURL tracks, newest first, one per line
# (e.g. "37"). The set is derived from the Dockerfile.1<minor> files in the given directory
# (default: the current directory, which is packages/kubernetes/template when run as a script),
# so adding a minor only requires adding its Dockerfile (see add-minor.sh).
function list_supported_minors() {
    local dir="${1:-.}"
    local dockerfile=
    local minor=
    for dockerfile in "$dir"/Dockerfile.1*; do
        [ -f "$dockerfile" ] || continue
        minor="${dockerfile##*/Dockerfile.1}"
        [[ "$minor" =~ ^[1-9][0-9]*$ ]] || continue
        echo "$minor"
    done | sort -rn
}

# versions_js_path prints the path of web/src/installers/versions.js relative to the template dir.
# KURL_VERSIONS_JS overrides it (used by tests).
function versions_js_path() {
    echo "${KURL_VERSIONS_JS:-../../../web/src/installers/versions.js}"
}

# minor_in_versions_js succeeds when the kubernetes array of versions.js ($2) lists a 1.<minor>.x version.
function minor_in_versions_js() {
    sed -n '/^[[:space:]]*kubernetes: \[/,/^[[:space:]]*\],/p' "$2" | grep -Eq "\"1\.${1}\.[0-9]+\""
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
        docker build -t "k8s1${minor}" - < "Dockerfile.1${minor}"
        local versions=()
        mapfile -t versions < <(docker run "k8s1${minor}" apt list -a kubelet 2>/dev/null | grep -Eo "1\.${minor}\.[0-9]+" | sort -rV | uniq)
        if [ ${#versions[@]} -gt 0 ]; then
            echo "Found latest version for Kubernetes 1.${minor}: ${versions[0]}"
            VERSIONS+=("${versions[0]}")
        fi
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
            printf 'Authorization: token %s\n' "$GITHUB_TOKEN" | curl -fsS --proto '=https' -H @- "$@" > "$body" || rc=$?
        else
            curl -fsS --proto '=https' "$@" < /dev/null > "$body" || rc=$?
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

    curl -fsSL --proto '=https' --proto-redir '=https' -o "$dir/kubeadm" "$url" || return 1

    local expected=
    expected="$(curl -fsSL --proto '=https' --proto-redir '=https' "${url}.sha256" | awk '{ print $1 }')"
    if ! [[ "$expected" =~ ^[0-9a-f]{64}$ ]]; then
        echo "ERROR: invalid sha256 published for kubeadm v${version}: '${expected}'" >&2
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
# cleans up its temp dir, and the Manifest is only moved into place once complete.
function generate_version_directory() (
    local version="$1"
    local workdir=
    workdir="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$workdir'" EXIT

    download_kubeadm "$version" "$workdir" || return 1

    # capture first so a kubeadm failure fails the script; never hand it our tokens
    local images=
    images="$(env -u GITHUB_TOKEN -u SHORTCUT_API_TOKEN "$workdir/kubeadm" config images list --kubernetes-version="${version}")" || return 1
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
    mv "$manifest" "../$version/Manifest"
)

# generate_conformance_package writes ../<version>/conformance/Manifest, only once complete.
function generate_conformance_package() {
    local version="$1"

    # --mode quick image
    local images=
    images="$(docker run --rm --entrypoint e2e.test "registry.k8s.io/conformance:v${version}" --list-images)" || return 1
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

# update_available_versions adds the newest VERSIONS entry of every supported minor right below
# its "// cron-kubernetes-update-1<minor>" marker in versions.js, unless already listed there.
function update_available_versions() {
    local versions_js=
    versions_js="$(versions_js_path)"
    local minor=
    local latest=
    local listed=
    for minor in $(list_supported_minors .); do
        latest="$(printf '%s\n' ${VERSIONS[@]+"${VERSIONS[@]}"} | grep "^1\.${minor}\." | head -n 1 || true)"
        [ -n "$latest" ] || continue
        # everything after the marker up to the end of the kubernetes array
        listed="$(sed "0,/cron-kubernetes-update-1${minor}/d" "$versions_js" | sed '/\],/,$d')"
        if ! grep -qF "\"${latest}\"" <<< "$listed" ; then
            sed -i "/cron-kubernetes-update-1${minor}/a\    \"${latest}\"\," "$versions_js"
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
