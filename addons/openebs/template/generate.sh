#!/bin/bash

set -euo pipefail

function generate() {
    local dir="../$version"

    mkdir -p "$dir"

    cp -r ./base/* "$dir"

    # actual openebs version
    sed -i "s/__OPENEBS_APP_VERSION__/$app_version/g" "$dir/install.sh"
    sed -i "s/__OPENEBS_APP_VERSION__/$app_version/g" "$dir/Manifest"

    local tmpdir=

    # localpv
    tmpdir="$dir/tmpdir"
    mkdir -p "$tmpdir"
    helm template -n '__OPENEBS_NAMESPACE__' openebs openebs-localpv/localpv-provisioner --version "$chart_version" \
        --include-crds \
        --set analytics.enabled=false \
        --set hostpathClass.enabled=false \
        --set localpv.resources.requests.cpu=100m \
        --set localpv.resources.limits.cpu=100m \
        --set localpv.resources.requests.memory=128Mi \
        --set localpv.resources.limits.memory=128Mi \
        > "$tmpdir/openebs.tmpl.yaml"

    $ksplit_path crdsplit "$tmpdir/"
    mv "$tmpdir/AllResources.yaml" "$dir/spec/openebs.tmpl.yaml"
#    mv "$tmpdir/CustomResourceDefinitions.yaml" "$dir/spec/crds/crds.yaml"
    rm -rf "$tmpdir"

    # get images in files
    mkdir -p "$tmpdir"
    grep 'image: ' "$dir/spec/openebs.tmpl.yaml" | sed 's/ *image: "*\(.*\)\/\(.*\):\([^"]*\)"*/image \2 \1\/\2:\3/' >> "$tmpdir/Manifest"
    sed -e '/ name: .*_IMAGE/,/ value: .*$/!d' "$dir/spec/openebs.tmpl.yaml" | grep ' value: ' | sed 's/ *value: "*\(.*\)\/\(.*\):\([^"]*\)"*/image \2 \1\/\2:\3/' >> "$tmpdir/Manifest"
    sort "$tmpdir/Manifest" | uniq >> "$dir/Manifest"
    rm -rf "$tmpdir"
}

function get_ksplit() {
    go install github.com/go-ksplit/ksplit/ksplit@v1.0.1
    set +u
    if [ -z "${GOPATH}" ]; then
        GOPATH="$HOME/go"
    fi
    set -u
    ksplit_path="$GOPATH/bin/ksplit"
}

function get_latest_release_version() {
    app_version=$(helm show chart --version "$version_flag" openebs-localpv/localpv-provisioner | \
        grep -i "^appVersion" | \
        grep -Eo "[0-9]\.[0-9]+\.[0-9]+")
    chart_version=$(helm show chart --version "$version_flag" openebs-localpv/localpv-provisioner | \
        grep -i "^version" | \
        grep -Eo "[0-9]+\.[0-9]+\.[0-9]+")
}

function add_as_latest() {
    if ! sed "0,/cron-openebs-update-$version_major/d" ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -qF "$version" ; then
        sed -i "/cron-openebs-update-$version_major$/a\    \"$version\"\," ../../../web/src/installers/versions.js
    fi
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

    # run the helm commands
    helm repo add openebs-localpv https://openebs.github.io/dynamic-localpv-provisioner
    helm repo update

    local app_version=
    local chart_version=

    get_latest_release_version # --version=^2.0.0

    local version_major=
    version_major=$(echo "$chart_version" | cut -d. -f1)

    local version="$app_version"

    if [ -d "../$version" ]; then
        if [ "$force_flag" == "1" ]; then
            echo "forcibly updating existing version of openebs"
            rm -rf "../$version"
        else
            echo "not updating existing version of openebs"
            return
        fi
    fi

    local ksplit_path=
    get_ksplit

    generate
    add_as_latest

    echo "openebs_version=$version" >> "$GITHUB_OUTPUT"
}

main "$@"
