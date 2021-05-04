#!/bin/bash

set -euo pipefail

VERSION=
function get_latest_version() {
    VERSION=$(helm show chart minio/minio-operator | \
        grep 'version: ' | \
        awk '{print $2}')
}

function generate() {
    local dir="../${VERSION}"

    # make the base set of files
    mkdir -p "${dir}"
    cp -r base/* "${dir}/"

    # make a temp directory to do work in
    local tmpdir=
    tmpdir="$(mktemp -p "${dir}" -d)"

    # run the helm commands
    helm repo add minio https://operator.min.io/
    helm repo update

    # generate values
    helm show values minio/minio-operator > "${tmpdir}/values.yaml"

    # split operator files
    helm template minio minio/minio-operator --namespace minio --version "${VERSION}" --values "${tmpdir}/values.yaml" --include-crds > "${tmpdir}/combined.yaml"

    # add images to manifest
    grep 'image: ' "${tmpdir}/combined.yaml" | sed 's/ *image: "*\(.*\)\/\(.*\):\([^"]*\)"*/image \2 \1\/\2:\3/' | sort | uniq > "${dir}/Manifest"

    split_yaml_files "${tmpdir}/combined.yaml" "${tmpdir}" "${dir}"
    rm -rf "${tmpdir}"
}

function add_as_latest() {
    if ! sed '0,/cron-minio-update/d' ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -q "${VERSION}" ; then
        sed -i "/cron-minio-update/a\    \"${VERSION}\"\," ../../../web/src/installers/versions.js
    fi
}

function split_yaml_files() {
    local combined="$1"
    local tmpdir="$2/split"
    local out="$3"

    mkdir -p "${tmpdir}"
    csplit --quiet --prefix="${tmpdir}/file" -b ".%03d.yaml" "${combined}" "/^---$/+1" "{*}"
    local tmpfile=
    for tmpfile in "${tmpdir}"/*.yaml ; do
        if grep -q "# Source: " "$tmpfile" ; then
            local basename=
            local filename=
            basename="$(basename "$(grep "# Source: " "$tmpfile" | sed 's/# Source: //')")"

            if [ "${basename}" = "tenant-secret.yaml" ]; then
                continue
            fi

            if grep "# Source: " "$tmpfile" | grep -q 'crds/' ; then
                filename="${out}/crds.yaml"
            else
                filename="${out}/operator/${basename}"
                if [ ! -f "${filename}" ]; then
                    insert_resources "${out}/operator/tmpl-kustomization.yaml" "${basename}"
                fi
            fi
            cat "${tmpfile}" >> "${filename}"
        fi
    done
    rm -rf "${tmpdir}"
}

function insert_resources() {
    local kustomization_file="$1"
    local resource_file="$2"

    if ! grep -q "resources:" "${kustomization_file}"; then
        echo "resources:" >> "${kustomization_file}"
    fi

    sed -i "/resources:.*/a - ${resource_file}" "${kustomization_file}"
}

function main() {
    VERSION=${1-}
    if [ -z "${VERSION}" ]; then
        get_latest_version
    fi

    rm -rf "../${VERSION}" # TODO: remove

    if [ -d "../${VERSION}" ]; then
        echo "Minio ${VERSION} add-on already exists"
        exit 0
    fi

    generate

    add_as_latest

    echo "::set-output name=rook_version::${VERSION}"
}

main "$@"
