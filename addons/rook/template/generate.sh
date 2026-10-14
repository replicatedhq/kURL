#!/bin/bash

set -euo pipefail

function get_latest_version() {
    helm search repo rook-release/rook-ceph 2>/dev/null | \
        grep -F 'rook-release/rook-ceph ' | \
        awk '{ print $2 }' | \
        sed 's/v//'
}

# rook_csi_images prints the CSI sidecar images for the Rook version being
# generated. Rook <= 1.20 pinned them as quoted image refs in
# deploy/examples/operator.yaml (e.g. provisioner: "registry.k8s.io/...:v1.2.3").
# Rook 1.21+ leaves them empty and lets the ceph-csi-operator subchart use its
# compiled-in defaults (internal/controller/defaults.go), so fall back to
# extracting them from the ceph-csi-operator release found in the rendered
# operator deployment.
function rook_csi_images() {
    local dir="$1"
    local github_content_url="$2"

    # transport failures must fail loudly, not fall through as "no images"
    local operator_yaml=
    if ! operator_yaml="$(curl -fsSL "${github_content_url}/deploy/examples/operator.yaml")"; then
        echo "failed to download rook v${VERSION} operator.yaml" >&2
        return 1
    fi
    local images=
    images="$(echo "${operator_yaml}" | grep -oE '"[^"]+/[^"]+:[^"]+"' || true)"
    # gate on CSI images actually being found, not just any quoted ref, so an
    # operator.yaml that no longer pins the sidecars cannot ship a Manifest
    # silently missing them. csi-provisioner is pinned by every rook release.
    if ! echo "${images}" | grep -q 'csi-provisioner'; then
        local csi_operator_version=
        csi_operator_version="$(grep -m1 -oE 'quay\.io/cephcsi/ceph-csi-operator:[^" ]+' "${dir}/operator/deployment.yaml" | cut -d: -f2 || true)"
        if [ -z "$csi_operator_version" ]; then
            echo "failed to find CSI images in operator.yaml and no ceph-csi-operator image in deployment.yaml" >&2
            return 1
        fi
        local defaults_go=
        if ! defaults_go="$(curl -fsSL "https://raw.githubusercontent.com/ceph/ceph-csi-operator/${csi_operator_version}/internal/controller/defaults.go")"; then
            echo "failed to download ceph-csi-operator ${csi_operator_version} defaults.go" >&2
            return 1
        fi
        images="$(echo "${defaults_go}" | sed -n '/imageDefaults/,/^}/p' | grep -oE '"[^"]+/[^"]+:[^"]+"' || true)"
        if ! echo "${images}" | grep -q 'csi-provisioner'; then
            echo "failed to extract CSI images from ceph-csi-operator ${csi_operator_version} defaults.go" >&2
            return 1
        fi
    fi
    echo "$images" | sed -E 's/"([^\/]+\/)?([^\/]+)\/([^:]+):([^" ]+)"/image \2-\3 \1\2\/\3:\4/'
}

function generate() {
    local dir="../${VERSION}"

    # make the base set of files
    mkdir -p "${dir}"
    cp -r base/* "${dir}/"

    # run the helm commands
    helm repo add rook-release https://charts.rook.io/release
    helm repo update

    # split operator files
    helm template replaceme rook-release/rook-ceph --version "${VERSION}" --values ./values.yaml -n rook-ceph --include-crds > "${dir}/operator/combined.yaml"
    # remove non-utf8 characters
    sed -i 's/–/-/g' "${dir}/operator/combined.yaml"
    sed -i 's/[“”]/"/g' "${dir}/operator/combined.yaml"
    split_resources "${dir}/operator/combined.yaml" "${dir}/operator" "${dir}/operator/kustomization.yaml"
    rm "${dir}/operator/combined.yaml"

    # apply crds separately
    sed -i '/^- resources\.yaml$/d' "${dir}/operator/kustomization.yaml"
    mv "${dir}/operator/resources.yaml" "${dir}/crds.yaml"

    local github_content_url="https://raw.githubusercontent.com/rook/rook/v${VERSION}"

    # download additional operator resources
    curl -fsSL -o "${dir}/operator/toolbox.yaml" "${github_content_url}/deploy/examples/toolbox.yaml"
    insert_resources "${dir}/operator/kustomization.yaml" "toolbox.yaml"

    # download cluster resources
    curl -fsSL -o "${dir}/cluster/cephfs/cephfs-storageclass.yaml" "${github_content_url}/deploy/examples/csi/cephfs/storageclass.yaml"
    # change CephFilesystem name from myfs to rook-shared-fs
    sed -i 's/myfs/rook-shared-fs/g' "${dir}/cluster/cephfs/cephfs-storageclass.yaml"
    curl -fsSL -o "${dir}/cluster/cluster.yaml" "${github_content_url}/deploy/examples/cluster.yaml"
    insert_resources "${dir}/cluster/kustomization.yaml" "cluster.yaml"
    curl -fsSL -o "${dir}/cluster/cephfs/filesystem.yaml" "${github_content_url}/deploy/examples/filesystem.yaml"
    # change CephFilesystem name from myfs to rook-shared-fs
    sed -i 's/myfs/rook-shared-fs/g' "${dir}/cluster/cephfs/filesystem.yaml"
    curl -fsSL -o "${dir}/cluster/object.yaml" "${github_content_url}/deploy/examples/object.yaml"
    insert_resources "${dir}/cluster/kustomization.yaml" "object.yaml"
    curl -fsSL -o "${dir}/cluster/tmpl-rbd-storageclass.yaml" "${github_content_url}/deploy/examples/csi/rbd/storageclass.yaml"
    sed -i 's/`/'"'"'/g' "${dir}/cluster/tmpl-rbd-storageclass.yaml" # escape backtics because they do not eval well
    sed -i -E "s/^( *)name: rook-ceph-block/\1name: \"\$\{STORAGE_CLASS:-default\}\"/" "${dir}/cluster/tmpl-rbd-storageclass.yaml"

    local ceph_image=
    ceph_image="$(grep ' image: '  "${dir}/cluster/cluster.yaml" | sed -E 's/ *image: "*([^" ]+).*/\1/')"

    sed -i "s/__CEPH_IMAGE__/$(echo "${ceph_image}" | sed 's/\//\\\//g')/" "${dir}/install.sh"
    sed -i "s/__ROOK_VERSION__/${VERSION}/" "${dir}/host-preflight.yaml"

    sed -i -E 's/( *)image: "*([^\/]+\/)?([^\/]+)\/([^:]+):([^" ]+).*/\1image: '"$(echo "${ceph_image}" | sed 's/\//\\\//g')"'/' "${dir}/operator/toolbox.yaml"

    # get images in files
    {   grep ' image: '  "${dir}/operator/deployment.yaml" | sed -E 's/ *image: "*([^\/]+\/)?([^\/]+)\/([^:]+):([^" ]+).*/image \2-\3 \1\2\/\3:\4/' ; \
        grep ' image: '  "${dir}/cluster/cluster.yaml" | sed -E 's/ *image: "*([^\/]+\/)?([^\/]+)\/([^:]+):([^" ]+).*/image \2-\3 \1\2\/\3:\4/' ; \
        rook_csi_images "${dir}" "${github_content_url}" ; \
    } >> "${dir}/Manifest"
}

function split_resources() {
    local combined="$1"
    local outdir="$2"
    local kustomization_file="$3"
    local tmpdir=
    tmpdir="$(mktemp -d -p "$outdir")"
    csplit --quiet --prefix="$tmpdir/out" -b ".%03d.yaml" "$combined" "/^---$/+1" "{*}"
    local files=("$tmpdir"/*.yaml)
    # reverse iterate over files so they are in order in kustomize resources
    for ((i=${#files[@]}-1; i>=0; i--)); do
        local tmpfile="${files[$i]}"
        if grep -q "# Source: " "$tmpfile" ; then
            local source=
            source="$(basename "$(grep "# Source: " "$tmpfile" | sed 's/# Source: //')")"
            local filename="$outdir/$source"
            if [ ! -f "$filename" ]; then
                insert_resources "$kustomization_file" "$(basename "$filename")"
            fi
            if [ -s "${filename}" ]; then
                echo "---" >> "${filename}"
            fi
            cat "${tmpfile}" >> "${filename}"
        fi
    done
    rm -rf "$tmpdir"
}

function insert_resources() {
    local kustomization_file="$1"
    local resource_file="$2"

    if ! grep -q "resources:" "$kustomization_file"; then
        echo "resources:" >> "$kustomization_file"
    fi

    sed -i "/resources:.*/a - $resource_file" "$kustomization_file"
}

function add_as_latest() {
    if ! sed '0,/cron-rook-update/d' ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -q "${VERSION}" ; then
        sed -i "/cron-rook-update/a\    \"${VERSION}\"\," ../../../web/src/installers/versions.js
    fi
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

    sed -i 's|^ROOK_STEP_VERSIONS=(.*|ROOK_STEP_VERSIONS=('"${steps[*]}"')|' ../../../hack/testdata/manifest/clean
    sed -i 's|^ROOK_STEP_VERSIONS=(.*|ROOK_STEP_VERSIONS=('"${steps[*]}"')|' ../../../scripts/Manifest
}

function parse_flags() {
    for i in "$@"; do
        case ${1} in
            --force)
                force_flag="1"
                shift
                ;;
            --version=*)
                version_flag="${i#*=}"
                shift
                ;;
            *)
                echo "Unknown flag $1"
                exit 1
                ;;
        esac
    done
}

function main() {
    local force_flag=
    local version_flag=

    parse_flags "$@"

    local VERSION="$version_flag"
    if [ -z "$VERSION" ]; then
        helm repo add rook-release https://charts.rook.io/release
        helm repo update
        VERSION="$(get_latest_version)"
    fi

    if [ -d "../$VERSION" ]; then
        if [ "$force_flag" == "1" ]; then
            echo "forcibly updating existing version of Rook"
            rm -rf "../$VERSION"
        else
            echo "not updating existing version of Rook"
            return
        fi
    fi

    generate

    add_as_latest

    generate_step_versions

    echo "rook_version=$VERSION" >> "$GITHUB_OUTPUT"
}

main "$@"
