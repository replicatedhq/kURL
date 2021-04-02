#!/bin/bash

set -euo pipefail

VERSION=""
function get_latest_release_version() {
    VERSION=$(helm show chart prometheus-community/kube-prometheus-stack | \
        grep -i "^appVersion" | \
        grep -Eo "[0-9]\.[0-9]+\.[0-9]+")
    CHARTVERSION=$(helm show chart prometheus-community/kube-prometheus-stack | \
        grep -i "^version" | \
        grep -Eo "[0-9]+\.[0-9]+\.[0-9]+")
}

function generate() {
    # make the base set of files
    mkdir -p "../${VERSION}"
    cp -r ./base/* "../${VERSION}"
    mkdir -p "../${VERSION}/crds"
    mkdir -p "../${VERSION}/operator"

    # get a copy of the stack with CRDs
    helm template replaceme prometheus-community/kube-prometheus-stack --version "$CHARTVERSION" --values ./values.yaml -n monitoring --include-crds > "../$VERSION/crds/crds-all.yaml"
    # get a copy of the stack without CRDs
    helm template replaceme prometheus-community/kube-prometheus-stack --version "$CHARTVERSION" --values ./values.yaml -n monitoring > "../$VERSION/operator/default.yaml"
    # get the prometheus adapter
    helm template replaceme prometheus-community/prometheus-adapter -n monitoring --include-crds > "../$VERSION/operator/adapter.yaml"

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

    # update names - 'prometheus-prometheus' to 'k8s' (as this has a PV attached)
    sed -i "s/prometheus-prometheus/k8s/g" "../$VERSION/operator/default.yaml"

    # get images in files
    grep 'image: '  "../$VERSION/operator/default.yaml" | sed 's/ *image: "*/image name /' | sed 's/"//' | sort | uniq > "../$VERSION/Manifest.tmp"
    grep 'image: '  "../$VERSION/operator/adapter.yaml" | sed 's/ *image: "*/image name /' | sed 's/"//' | sort | uniq >> "../$VERSION/Manifest.tmp"

    cat "../$VERSION/Manifest.tmp" | awk '/image name/ { $2 = NR } { print $1 " prometheusimage" $2 " " $3 }' >> "../$VERSION/Manifest"
    rm "../$VERSION/Manifest.tmp"
}

function add_as_latest() {
    sed -i "/cron-prometheus-update/a\    \"${VERSION}\"\," ../../../web/src/installers/versions.js
}

function main() {
    # run the helm commands
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update

    get_latest_release_version

    if [ -d "../${VERSION}" ]; then
        rm -rf "../${VERSION}"
    else
        add_as_latest
    fi

    generate

    echo "::set-output name=prometheus_version::$VERSION"
}

main "$@"
