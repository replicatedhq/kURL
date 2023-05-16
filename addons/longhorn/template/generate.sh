#!/bin/bash

set -euo pipefail

VERSION=""

function get_latest_release_version() {
  VERSION=$(curl --silent "https://api.github.com/repos/longhorn/longhorn/releases/latest" | # Get latest release from GitHub api
    grep '"tag_name":' |                                                                     # Get tag line
    sed -E 's/.*"v([^"]+)".*/\1/'                                                             # Pluck JSON value
  )
}

KSPLITPATH=""
function get_ksplit() {
    go install github.com/go-ksplit/ksplit/ksplit@v1.0.1
    set +u
    if [ -z "${GOPATH}" ]; then
        GOPATH="$HOME/go"
    fi
    set -u
    KSPLITPATH="$GOPATH/bin/ksplit"
}

function generate() {
    # make the base set of files
    mkdir -p "../${VERSION}"
    mkdir -p "../${VERSION}/tmp"
    cp -r ./base/* "../${VERSION}"

    # get the raw yaml for the release
    curl --silent "https://raw.githubusercontent.com/longhorn/longhorn/v$VERSION/deploy/longhorn.yaml" > "../${VERSION}/tmp/longhorn.yaml"

    # cd to allow ksplit to include the path, and then cd back

    ( cd ..; $KSPLITPATH crdsplit "${VERSION}/tmp/" )

    # disable upgrade checker
    sed -i 's/upgrade-checker:/upgrade-checker: false/' "../${VERSION}/tmp/AllResources.yaml"

    # add priority-class
    sed -i 's/priority-class:/priority-class: system-node-critical/' "../${VERSION}/tmp/AllResources.yaml"

    split_resources "../${VERSION}/tmp/AllResources.yaml" "../${VERSION}/yaml" "../${VERSION}/yaml/kustomization.yaml"

    mv "../${VERSION}/yaml/storageclass.yaml" "../${VERSION}/template/storageclass.yaml"
    sed -i 's/is-default-class: "true"/is-default-class: "$LONGHORN_IS_DEFAULT_STORAGECLASS"/' "../${VERSION}/template/storageclass.yaml"

    mv "../${VERSION}/tmp/CustomResourceDefinitions.yaml" "../${VERSION}/crds.yaml"
    rm -rf "../${VERSION}/tmp"

    # get the images for the release
    curl --silent "https://raw.githubusercontent.com/longhorn/longhorn/v$VERSION/deploy/longhorn-images.txt" | sed 's/\(.*\)\/\(.*\):\([^"]*\)/image \2 \1\/\2:\3/' >> "../${VERSION}/Manifest"

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
            local filename="$(unique_filename "$outdir/$source")"
            mv "$tmpfile" "$filename"
            insert_resources "$kustomization_file" "$(basename $filename)"
        fi
    done
    rm -rf "$tmpdir"
}

function unique_filename() {
    local filename="$1"
    local extension="$(echo "$filename" | rev | cut -d'.' -f1 | rev)"
    local base="${filename::-(${#extension}+1)}"
    local i=0
    while [ -f "$filename" ]; do
        let "i=i+1"
        filename="$base.$i.$extension"
    done
    echo "$filename"
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
    if ! sed '0,/cron-longhorn-update/d' ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -q "${VERSION}" ; then
        sed -i "/cron-longhorn-update/a\    \"${VERSION}\"\," ../../../web/src/installers/versions.js
    fi
}

function main() {
    get_latest_release_version
    # The version 1.2.6 is lower than the latest added and it does not have
    # all manifest which causes the script fail
    if [ "${VERSION}" == "1.2.6" ]; then
        echo "ignore version 1.2.6"
        return
    fi

    if [ -d "../${VERSION}" ]; then
        if [ $# -ge 1 ] && [ "$1" == "force" ]; then
            echo "forcibly updating existing version of longhorn"
            rm -rf "../${VERSION}"
        else
            echo "not updating existing version of longhorn"
            return
        fi
    else
        add_as_latest
    fi

    get_ksplit

    generate

    echo "longhorn_version=$VERSION" >> "$GITHUB_OUTPUT"
}

main "$@"
