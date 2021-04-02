#!/bin/bash

set -euo pipefail

VERSION=
function get_latest_version() {
    # latest 1.4.x version
    VERSION=$(curl -s https://api.github.com/repos/rook/rook/releases | \
        grep '"tag_name": ' | \
        grep -Eo "1\.4\.[0-9]+" | \
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
    helm template replaceme rook-release/rook-ceph --version "${VERSION}" --values ./values.yaml -n monitoring --include-crds > "${dir}/operator/combined.yaml"
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
    insert_resources "${dir}/operator/kustomization.yaml" "${dir}/operator/toolbox.yaml"

    # download cluster resources
    mkdir -p "${dir}/cluster"
    curl -fsSL -o "${dir}/cluster/cluster.yaml" "${github_content_url}/cluster/examples/kubernetes/ceph/cluster.yaml"
    insert_resources "${dir}/cluster/kustomization.yaml" "cluster.yaml"
    curl -fsSL -o "${dir}/cluster/pool.yaml" "${github_content_url}/cluster/examples/kubernetes/ceph/pool.yaml"
    insert_resources "${dir}/cluster/kustomization.yaml" "pool.yaml"
    curl -fsSL -o "${dir}/cluster/tmpl-rbd-storageclass.yaml" "${github_content_url}/cluster/examples/kubernetes/ceph/csi/rbd/storageclass.yaml"
    sed -i 's/^\s*  name: rook-ceph-block/  name: \$\{STORAGE_CLASS:-default\}/' "${dir}/cluster/tmpl-rbd-storageclass.yaml"
    insert_resources "${dir}/cluster/kustomization.yaml" "tmpl-rbd-storageclass.yaml"
    curl -fsSL -o "${dir}/cluster/object.yaml" "${github_content_url}/cluster/examples/kubernetes/ceph/object.yaml"
    sed -i 's/^\s*  name: my-store/  name: rook-ceph-store/' "${dir}/cluster/object.yaml"
    insert_resources "${dir}/cluster/kustomization.yaml" "object.yaml"
    curl -fsSL -o "${dir}/cluster/filesystem.yaml" "${github_content_url}/cluster/examples/kubernetes/ceph/filesystem.yaml"
    sed -i 's/^\s*  name: myfs/  name: rook-shared-fs/' "${dir}/cluster/filesystem.yaml"
    insert_resources "${dir}/cluster/kustomization.yaml" "filesystem.yaml"
    curl -fsSL -o "${dir}/cluster/cephfs-storageclass.yaml" "${github_content_url}/cluster/examples/kubernetes/ceph/csi/cephfs/storageclass.yaml"
    sed -i 's/^\s*  fsName: myfs/  fsName: rook-shared-fs/' "${dir}/cluster/cephfs-storageclass.yaml"
    sed -i 's/^\s*  pool: myfs-data0/  pool: rook-shared-fs-data0/' "${dir}/cluster/cephfs-storageclass.yaml"
    insert_resources "${dir}/cluster/kustomization.yaml" "tmpl-cephfs-storageclass.yaml"
    exit

    # remove non-CRD yaml from crds
    diff -U $(wc -l < "../$VERSION/crds/crds-all.yaml") "../$VERSION/crds/crds-all.yaml" "../$VERSION/operator/default.yaml" | sed '/^--- \.\.\//d' | sed -n 's/^-//p' > "../$VERSION/crds/crds.yaml" || true
    rm "../$VERSION/crds/crds-all.yaml"

    # fix names (replaceme-grafana -> grafana)
    sed -i 's/replaceme-//g' "../$VERSION/operator/default.yaml"
    sed -i 's/replaceme-//g' "../$VERSION/operator/adapter.yaml"

    # fix replaceme everywhere else
    sed -i "s/replaceme/v$VERSION/g" "../$VERSION/operator/default.yaml"
    sed -i "s/replaceme/v$VERSION/g" "../$VERSION/operator/adapter.yaml"

    # update version in install.sh
    sed -i "s/__PROMETHEUS_VERSION__/$VERSION/g" "../$VERSION/install.sh"

    # get images in files
    grep 'image: '  "../$VERSION/operator/default.yaml" | sed 's/ *image: "*/image name /' | sed 's/"//' | sort | uniq > "../$VERSION/Manifest"
    grep 'image: '  "../$VERSION/operator/adapter.yaml" | sed 's/ *image: "*/image name /' | sed 's/"//' | sort | uniq >> "../$VERSION/Manifest"
}

function add_as_latest() {
    sed -i "/cron-rook-update/a\    \"${VERSION}\"\," ../../../web/src/installers/versions.js
}

function insert_resources() {
    local kustomization_file="$1"
    local resource_file="$2"

    if ! grep -q "resources" "$kustomization_file"; then
        echo "resources:" >> "$kustomization_file"
    fi

    sed -i "/resources.*/a - $resource_file" "$kustomization_file"
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
