#!/bin/bash

set -euo pipefail

function get_latest_release_version() {
    VERSION=$(helm show chart prometheus-community/kube-prometheus-stack | \
        grep -i "^appVersion" | \
        grep -Eo "[0-9]\.[0-9]+\.[0-9]+")
    CHARTVERSION=$(helm show chart prometheus-community/kube-prometheus-stack | \
        grep -i "^version" | \
        grep -Eo "[0-9]+\.[0-9]+\.[0-9]+")
}

function generate() {
    local capabilities="--kube-version v1.22 -a networking.k8s.io/v1 -a rbac.authorization.k8s.io/v1 -a apiregistration.k8s.io/v1"
    
    # make the base set of files
    mkdir -p "../${VERSION}-${CHARTVERSION}"
    cp -r ./base/* "../${VERSION}-${CHARTVERSION}"
    mkdir -p "../${VERSION}-${CHARTVERSION}/crds"
    mkdir -p "../${VERSION}-${CHARTVERSION}/operator"

    # get a copy of the stack with CRDs
    helm template replaceme prometheus-community/kube-prometheus-stack \
        $capabilities \
        --version "$CHARTVERSION" \
        --values ./values.yaml \
        -n monitoring \
        --include-crds \
        > "../$VERSION-$CHARTVERSION/crds/crds-all.yaml"
    # get a copy of the stack without CRDs
    helm template replaceme prometheus-community/kube-prometheus-stack \
        $capabilities \
        --version "$CHARTVERSION" \
        --values ./values.yaml \
        -n monitoring \
        > "../$VERSION-$CHARTVERSION/operator/default.yaml"
    # get the prometheus adapter
    helm template replaceme prometheus-community/prometheus-adapter \
        $capabilities \
        -n monitoring \
        --set "prometheus.url=http://prometheus-k8s" \
        --include-crds \
        > "../$VERSION-$CHARTVERSION/operator/adapter.yaml"

    # remove non-CRD yaml from crds
    diff -U $(wc -l < "../$VERSION-$CHARTVERSION/crds/crds-all.yaml") "../$VERSION-$CHARTVERSION/crds/crds-all.yaml" "../$VERSION-$CHARTVERSION/operator/default.yaml" | sed '/^--- \.\.\//d' | sed -n 's/^-//p' > "../$VERSION-$CHARTVERSION/crds/crds.yaml" || true
    rm "../$VERSION-$CHARTVERSION/crds/crds-all.yaml"

    # fix names (replaceme-grafana -> grafana)
    sed -i 's/replaceme-//g' "../$VERSION-$CHARTVERSION/operator/default.yaml"
    sed -i 's/replaceme-//g' "../$VERSION-$CHARTVERSION/operator/adapter.yaml"

    # fix replaceme everywhere else
    sed -i "s/replaceme/v$VERSION-$CHARTVERSION/g" "../$VERSION-$CHARTVERSION/operator/default.yaml"
    sed -i "s/replaceme/v$VERSION-$CHARTVERSION/g" "../$VERSION-$CHARTVERSION/operator/adapter.yaml"

    # update version in install.sh
    sed -i "s/__PROMETHEUS_VERSION__/$VERSION-$CHARTVERSION/g" "../$VERSION-$CHARTVERSION/install.sh"

    # update names - 'prometheus-prometheus' to 'k8s' (as this has a PV attached)
    sed -i "s/prometheus-prometheus/k8s/g" "../$VERSION-$CHARTVERSION/operator/default.yaml"

    # change service name "k8s" to "prometheus-k8s" for consistency with previous versions
    # replace first occurance of " name: k8s" after "kube-prometheus-stack/templates/prometheus/service.yaml" with " name: prometheus-k8s"
    sed -i -e '/kube-prometheus-stack\/templates\/prometheus\/service.yaml/!b' -e ':a' -e "s/ name: k8s/ name: prometheus-k8s/;t trail" -e 'n;ba' -e ':trail' -e 'n;btrail' "../$VERSION-$CHARTVERSION/operator/default.yaml"
    sed -i 's/http:\/\/k8s/http:\/\/prometheus-k8s/g' "../$VERSION-$CHARTVERSION/operator/default.yaml"

    # get images in files
    grep 'image: '  "../$VERSION-$CHARTVERSION/operator/default.yaml" | sed 's/ *image: "*\(.*\)\/\(.*\):\([^"]*\)"*/image \2 \1\/\2:\3/' >> "../$VERSION-$CHARTVERSION/Manifest.tmp"
    grep 'image: '  "../$VERSION-$CHARTVERSION/operator/adapter.yaml" | sed 's/ *image: "*\(.*\)\/\(.*\):\([^"]*\)"*/image \2 \1\/\2:\3/' >> "../$VERSION-$CHARTVERSION/Manifest.tmp"

    # get prometheus-config-reloader image '            - --prometheus-config-reloader=quay.io/prometheus-operator/prometheus-config-reloader:v0.46.0'
    grep 'prometheus-config-reloader=' "../$VERSION-$CHARTVERSION/operator/default.yaml" | sed 's/.*--prometheus-config-reloader=\(.*\)\/\(.*\):\([^"]*\)/image \2 \1\/\2:\3/' >> "../$VERSION-$CHARTVERSION/Manifest.tmp"

    # deduplicate manifest
    cat "../$VERSION-$CHARTVERSION/Manifest.tmp" | sort | uniq >> "../$VERSION-$CHARTVERSION/Manifest"
    rm "../$VERSION-$CHARTVERSION/Manifest.tmp"
}

function add_as_latest() {
    sed -i "/cron-prometheus-update/a\    \"${VERSION}-${CHARTVERSION}\"\," ../../../web/src/installers/versions.js
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
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update

    local VERSION=
    local CHARTVERSION=
    if [ -n "$version_flag" ]; then
        VERSION="$( echo "$version_flag" | cut -d'-' -f1 )"
        CHARTVERSION="$( echo "$version_flag" | cut -d'-' -f2 )"
    else
        get_latest_release_version
    fi

    if [ -d "../${VERSION}-${CHARTVERSION}" ]; then
        if [ "$force_flag" == "1" ]; then
            echo "forcibly updating existing version of prometheus"
            rm -rf "../${VERSION}-${CHARTVERSION}"
        else
            echo "not updating existing version of prometheus"
            return
        fi
    else
        add_as_latest
    fi

    generate

    echo "prometheus_version=$VERSION-$CHARTVERSION" >> "$GITHUB_OUTPUT"
}

main "$@"
