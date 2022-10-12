#!/bin/bash

set -euo pipefail

function get_latest_19x_version() {
    curl -s https://api.github.com/repos/rook/rook/releases | \
        grep '"tag_name": ' | \
        grep -Eo "1\.9\.[0-9]+" | \
        head -1
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
    curl -fsSL -o "${dir}/cluster/cephfs-storageclass.yaml" "${github_content_url}/deploy/examples/csi/cephfs/storageclass.yaml"
    # change CephFilesystem name from myfs to rook-shared-fs
    sed -i 's/myfs/rook-shared-fs/g' "${dir}/cluster/cephfs-storageclass.yaml"
    curl -fsSL -o "${dir}/cluster/cluster.yaml" "${github_content_url}/deploy/examples/cluster.yaml"
    insert_resources "${dir}/cluster/kustomization.yaml" "cluster.yaml"
    curl -fsSL -o "${dir}/cluster/filesystem.yaml" "${github_content_url}/deploy/examples/filesystem.yaml"
    # change CephFilesystem name from myfs to rook-shared-fs
    sed -i 's/myfs/rook-shared-fs/g' "${dir}/cluster/filesystem.yaml"
    curl -fsSL -o "${dir}/cluster/object.yaml" "${github_content_url}/deploy/examples/object.yaml"
    insert_resources "${dir}/cluster/kustomization.yaml" "object.yaml"
    curl -fsSL -o "${dir}/cluster/tmpl-rbd-storageclass.yaml" "${github_content_url}/deploy/examples/csi/rbd/storageclass.yaml"
    sed -i 's/`/'"'"'/g' "${dir}/cluster/tmpl-rbd-storageclass.yaml" # escape backtics because they do not eval well
    sed -i -E "s/^( *)name: rook-ceph-block/\1name: \"\$\{STORAGE_CLASS:-default\}\"/" "${dir}/cluster/tmpl-rbd-storageclass.yaml"

    local ceph_image=
    ceph_image="$(grep ' image: '  "${dir}/cluster/cluster.yaml" | sed -E 's/ *image: "*([^" ]+).*/\1/')"

    # Upgrading passed v16.2.6 based on this note in the Rook docs
    # https://www.rook.io/docs/rook/v1.6/ceph-upgrade.html#ceph-version-upgrades
    # WARNING: There is a notice from Ceph for users upgrading to Ceph Pacific v16.2.6 or lower from an earlier major version of Ceph. If you are upgrading to Ceph Pacific (v16), please upgrade to v16.2.7 or higher if possible.
    if echo "$ceph_image" | grep -q ":v16\.2" ; then
        local ceph_version_patch="$(echo "$ceph_image" | grep -o "v[0-9]*\.[0-9]*\.[0-9]*" | sed "s/v[0-9]*\.[0-9]*\.\([0-9]*\).*/\1/")"
        if [ "$ceph_version_patch" -lt "7" ]; then
            ceph_image="$(echo "$ceph_image" | sed "s/v[0-9]*\.[0-9]*\.[0-9]*/v16.2.7/")"
        fi
    fi

    sed -i "s/__CEPH_IMAGE__/$(echo "${ceph_image}" | sed 's/\//\\\//g')/" "${dir}/install.sh"

    # get images in files
    {   grep ' image: '  "${dir}/operator/deployment.yaml" | sed -E 's/ *image: "*([^\/]+\/)?([^\/]+)\/([^:]+):([^" ]+).*/image \2-\3 \1\2\/\3:\4/' ; \
        grep ' image: '  "${dir}/cluster/cluster.yaml" | sed -E 's/ *image: "*([^\/]+\/)?([^\/]+)\/([^:]+):([^" ]+).*/image \2-\3 \1\2\/\3:\4/' ; \
        curl -fsSL "${github_content_url}/deploy/examples/operator.yaml" | grep '_IMAGE: ' | sed -E 's/.*_IMAGE: "*([^\/]+\/)?([^\/]+)\/([^:]+):([^" ]+).*/image \2-\3 \1\2\/\3:\4/' ; \
    } >> "${dir}/Manifest"
}

function split_resources() {
    local combined="$1"
    local outdir="$2"
    local kustomization_file="$3"
    local tmpdir="$(mktemp -d -p $outdir)"
    csplit --quiet --prefix="$tmpdir/out" -b ".%03d.yaml" $combined "/^---$/+1" "{*}"
    local files=("$tmpdir"/*.yaml)
    # reverse iterate over files so they are in order in kustomize resources
    for ((i=${#files[@]}-1; i>=0; i--)); do
        local tmpfile="${files[$i]}"
        if grep -q "# Source: " "$tmpfile" ; then
            local source="$(basename "$(grep "# Source: " "$tmpfile" | sed 's/# Source: //')")"
            local filename="$outdir/$source"
            if [ ! -f "${filename}" ]; then
                insert_resources "$kustomization_file" "$(basename $filename)"
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

function main() {
    VERSION="${1-}"
    if [ "${1-}" == "force" ]; then
        VERSION=
    fi
    if [ -z "$VERSION" ]; then
        VERSION="$(get_latest_19x_version)"
    fi

    if [ -d "../$VERSION" ]; then
        if [ "${1-}" == "force" ] || [ "${2-}" == "force" ]; then
            echo "forcibly updating existing version of Rook"
            rm -rf "../$VERSION"
        else
            echo "not updating existing version of Rook"
            return
        fi
    fi

    generate

    add_as_latest

    echo "::set-output name=rook_version::$VERSION"
}

main "$@"
