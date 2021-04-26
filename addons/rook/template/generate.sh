#!/bin/bash

set -euo pipefail

VERSION=
function get_latest_version() {
    # latest 1.5.x version
    VERSION=$(curl -s https://api.github.com/repos/rook/rook/releases | \
        grep '"tag_name": ' | \
        grep -Eo "1\.5\.[0-9]+" | \
        head -1)
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
    mkdir -p "${dir}/operator/tmp"
    csplit --quiet --prefix="${dir}/operator/tmp/out" -b ".%03d.yaml" "${dir}/operator/combined.yaml" "/^---$/+1" "{*}"
    for tmpfile in "${dir}"/operator/tmp/*.yaml ; do
        if grep -q "# Source: " "$tmpfile" ; then
            local basename=
            local filename=
            basename="$(basename "$(grep "# Source: " "$tmpfile" | sed 's/# Source: //')")"
            filename="${dir}/operator/${basename}"
            if [ ! -f "${filename}" ]; then
                insert_resources "${dir}/operator/kustomization.yaml" "${basename}"
            fi
            cat "${tmpfile}" >> "${filename}"
        fi
    done
    rm -rf "${dir}/operator/tmp" "${dir}/operator/combined.yaml"

    local github_content_url="https://raw.githubusercontent.com/rook/rook/v${VERSION}"

    # download additional operator resources
    curl -fsSL -o "${dir}/operator/toolbox.yaml" "${github_content_url}/cluster/examples/kubernetes/ceph/toolbox.yaml"
    insert_resources "${dir}/operator/kustomization.yaml" "toolbox.yaml"

    # download cluster resources
    curl -fsSL -o "${dir}/cluster/cephfs-storageclass.yaml" "${github_content_url}/cluster/examples/kubernetes/ceph/csi/cephfs/storageclass.yaml"
    curl -fsSL -o "${dir}/cluster/cluster.yaml" "${github_content_url}/cluster/examples/kubernetes/ceph/cluster.yaml"
    insert_resources "${dir}/cluster/kustomization.yaml" "cluster.yaml"
    curl -fsSL -o "${dir}/cluster/filesystem.yaml" "${github_content_url}/cluster/examples/kubernetes/ceph/filesystem.yaml"
    curl -fsSL -o "${dir}/cluster/object.yaml" "${github_content_url}/cluster/examples/kubernetes/ceph/object.yaml"
    insert_resources "${dir}/cluster/kustomization.yaml" "object.yaml"
    curl -fsSL -o "${dir}/cluster/tmpl-rbd-storageclass.yaml" "${github_content_url}/cluster/examples/kubernetes/ceph/csi/rbd/storageclass.yaml"
    sed -i 's/`/'"'"'/g' "${dir}/cluster/tmpl-rbd-storageclass.yaml" # escape backtics because they do not eval well
    sed -i -E "s/^( *)name: rook-ceph-block/\1name: \"\$\{STORAGE_CLASS:-default\}\"/" "${dir}/cluster/tmpl-rbd-storageclass.yaml"

    local ceph_image=
    ceph_image="$(grep ' image: '  "${dir}/cluster/cluster.yaml" | sed -E 's/ *image: "*([^" ]+).*/\1/')"
    sed -i "s/__IMAGE__/$(echo "${ceph_image}" | sed 's/\//\\\//')/" "${dir}/install.sh"

    # get images in files
    {   grep ' image: '  "${dir}/operator/deployment.yaml" | sed -E 's/ *image: "*([^\/]+\/)?([^\/]+)\/([^:]+):([^" ]+).*/image \2-\3 \1\2\/\3:\4/' ; \
        grep ' image: '  "${dir}/cluster/cluster.yaml" | sed -E 's/ *image: "*([^\/]+\/)?([^\/]+)\/([^:]+):([^" ]+).*/image \2-\3 \1\2\/\3:\4/' ; \
        curl -fsSL "${github_content_url}/cluster/examples/kubernetes/ceph/operator.yaml" | grep '_IMAGE: ' | sed -E 's/.*_IMAGE: "*([^\/]+\/)?([^\/]+)\/([^:]+):([^" ]+).*/image \2-\3 \1\2\/\3:\4/' ; \
    } >> "${dir}/Manifest"
}

function add_as_latest() {
    if ! sed '0,/cron-rook-update/d' ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -q "${VERSION}" ; then
        sed -i "/cron-rook-update/a\    \"${VERSION}\"\," ../../../web/src/installers/versions.js
    fi
}

function insert_resources() {
    local kustomization_file="$1"
    local resource_file="$2"

    if ! grep -q "resources:" "$kustomization_file"; then
        echo "resources:" >> "$kustomization_file"
    fi

    sed -i "/resources:.*/a - $resource_file" "$kustomization_file"
}

function main() {
    VERSION=${1-}
    if [ -z "$VERSION" ]; then
        get_latest_version
    fi

    if [ -d "../$VERSION" ]; then
        echo "Rook ${VERSION} add-on already exists"
        exit 0
    fi

    generate

    add_as_latest

    echo "::set-output name=rook_version::$VERSION"
}

main "$@"
