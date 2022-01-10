#!/bin/bash

set -euo pipefail

# Populate VERSIONS array latest kURL-support versions (1.19, 1.20, 1.21) available
VERSIONS=()
function find_available_versions() {
    docker build -t k8s - < Dockerfile
    # VERSIONS=($(docker run k8s apt list -a kubelet 2>/dev/null | grep -Eo '1\.[2][0-9]\.[0-9]+' | sort -rV | uniq))
    # echo "Found ${#VERSIONS[*]} versions for Kubernetes 1.20+: ${VERSIONS[*]}"

    local versions122=($(docker run k8s apt list -a kubelet 2>/dev/null | grep -Eo '1\.22\.[0-9]+' | sort -rV | uniq))
    if [ ${#versions122[@]} -gt 0 ]; then
        echo "Found latest version for Kubernetes 1.22: ${versions122[0]}"
        VERSIONS+=("${versions122[0]}")
    fi

    local versions121=($(docker run k8s apt list -a kubelet 2>/dev/null | grep -Eo '1\.21\.[0-9]+' | sort -rV | uniq))
    if [ ${#versions121[@]} -gt 0 ]; then
        echo "Found latest version for Kubernetes 1.21: ${versions121[0]}"
        VERSIONS+=("${versions121[0]}")
    fi

    local versions120=($(docker run k8s apt list -a kubelet 2>/dev/null | grep -Eo '1\.20\.[0-9]+' | sort -rV | uniq))
    if [ ${#versions120[@]} -gt 0 ]; then
        echo "Found latest version for Kubernetes 1.20: ${versions120[0]}"
        VERSIONS+=("${versions120[0]}")
    fi

    echo "Found ${#VERSIONS[*]} versions for Kubernetes: ${VERSIONS[*]}"
}

function generate_version_directory() {
    local version="$1"

    mkdir -p "../$version"
    rm -f "../$version/Manifest"

    curl -LO https://dl.k8s.io/release/v${version}/bin/linux/amd64/kubeadm
    chmod +x kubeadm
    mv kubeadm /tmp

    while read -r image; do
        # k8s.gcr.io/kube-apiserver:v1.20.2 -> kube-apiserver
        local name=$(echo "$image" | awk -F':' '{ print $1 }' | awk -F '/' '{ print $2 }')
        echo "image ${name} ${image}" >> "../$version/Manifest"
    done < <(/tmp/kubeadm config images list --kubernetes-version=${version})

    # hardcode existing versions to 1.20.0 since it's tested
    local criToolsVersion=$(curl -H "Authorization: token ${GITHUB_TOKEN}" -s https://api.github.com/repos/kubernetes-sigs/cri-tools/releases | \
        grep '"tag_name": ' | \
        grep -Eo "1\.20\.[0-9]+" | \
        head -1)
    # Kubernetes 1.21+ gets latest crictl release with same minor
    local minor=$(echo "$version" | awk -F'.' '{ print $2 }')
    if [ "$minor" -ge 20 ]; then
        criToolsVersion=$(curl -H "Authorization: token ${GITHUB_TOKEN}" -s https://api.github.com/repos/kubernetes-sigs/cri-tools/releases | \
            grep '"tag_name": ' | \
            ( grep -Eo "1\.${minor}\.[0-9]+" || true ) | \
            head -1)
    fi

    # Fallback: Kubernetes 1.23 doesn't have a version of criTools as of 2021-12-13
    # Any latest version of criTools will work for any version of Kubernetes >=1.16, so this is a safe operation
    if [ -z "$criToolsVersion" ]; then
        criToolsVersion=$(curl -H "Authorization: token ${GITHUB_TOKEN}" -s https://api.github.com/repos/kubernetes-sigs/cri-tools/releases | \
        grep '"tag_name": ' | \
        grep -Eo "1\.[2-9][0-9]\.[0-9]+"| \
        head -1)
    fi

    echo "" >> "../$version/Manifest"
    echo "asset kubeadm https://storage.googleapis.com/kubernetes-release/release/v$version/bin/linux/amd64/kubeadm" >> "../$version/Manifest"
    echo "asset crictl-linux-amd64.tar.gz https://github.com/kubernetes-sigs/cri-tools/releases/download/v$criToolsVersion/crictl-v$criToolsVersion-linux-amd64.tar.gz" >> "../$version/Manifest"

    echo "" >> "../$version/Manifest"
    echo "asset kustomize-v2.0.3 https://github.com/kubernetes-sigs/kustomize/releases/download/v2.0.3/kustomize_2.0.3_linux_amd64" >> "../$version/Manifest"
    echo "asset kustomize-v3.5.4.tar.gz https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv3.5.4/kustomize_v3.5.4_linux_amd64.tar.gz" >> "../$version/Manifest"
}

function generate_conformance_package() {
    local version="$1"

    mkdir -p "../$version/conformance"
    rm -f "../$version/conformance/Manifest"

    # add conformance image for sonobuoy to manifest
    echo "image conformance k8s.gcr.io/conformance:v${version}" > "../$version/conformance/Manifest"

    # image required for sonobuoy --mode=quick
    local minor=$(echo "$version" | awk -F'.' '{ print $2 }')
    if [ "$minor" -ge "21" ]; then
        echo "image nginx k8s.gcr.io/e2e-test-images/nginx:1.14-1" >> "../$version/conformance/Manifest"
    else
        echo "image nginx-1.14-alpine docker.io/library/nginx:1.14-alpine" >> "../$version/conformance/Manifest"
    fi

    # NOTE: full conformance suite images are not yet included in this package
    # local tmpdir=
    # tmpdir="$(mktemp -d)"
    # curl -L -o "${tmpdir}/sonobuoy.tar.gz" https://github.com/vmware-tanzu/sonobuoy/releases/download/v${VERSION}/sonobuoy_${VERSION}_linux_amd64.tar.gz && \
    #     tar xzvf "${tmpdir}/sonobuoy.tar.gz" -C "${tmpdir}"
    # "${tmpdir}/sonobuoy" images pull --dry-run 2>&1 \
    #     | grep 'Pulling image:' \
    #     | sed 's/^.*Pulling image: \(.*\)"$/\1/' \
    #     | grep -v authenticated \
    #     | grep -v invalid \
    #     | sed -E "s/^(.*)\/([^:]+):(.+)/image \2-\3 \1\/\2:\3/" >> "../${VERSION}/Manifest"
    # rm -r "${tmpdir}"
}

function update_available_versions() {

    local version122=( $( for i in "${VERSIONS[@]}" ; do echo $i ; done | grep '^1.22' ) )
    if [ ${#version122[@]} -gt 0 ]; then
        if ! sed '0,/cron-kubernetes-update-122/d' ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -q "${version122[0]}" ; then
            sed -i "/cron-kubernetes-update-122/a\    \"${version122[0]}\"\," ../../../web/src/installers/versions.js
        fi
    fi

    local version121=( $( for i in "${VERSIONS[@]}" ; do echo $i ; done | grep '^1.21' ) )
    if [ ${#version121[@]} -gt 0 ]; then
        if ! sed '0,/cron-kubernetes-update-121/d' ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -q "${version121[0]}" ; then
            sed -i "/cron-kubernetes-update-121/a\    \"${version121[0]}\"\," ../../../web/src/installers/versions.js
        fi
    fi

    local version120=( $( for i in "${VERSIONS[@]}" ; do echo $i ; done | grep '^1.20' ) )
    if [ ${#version120[@]} -gt 0 ]; then
        if ! sed '0,/cron-kubernetes-update-120/d' ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -q "${version120[0]}" ; then
            sed -i "/cron-kubernetes-update-120/a\    \"${version120[0]}\"\," ../../../web/src/installers/versions.js
        fi
    fi

}

function main() {
    VERSIONS=("$@")
    if [ ${#VERSIONS[@]} -eq 0 ]; then
        find_available_versions
    fi

    for version in ${VERSIONS[*]}; do
        generate_version_directory "${version}"
        generate_conformance_package "${version}"
    done
    echo "::set-output name=kubernetes_version::${VERSIONS[*]}"

    update_available_versions
}

main "$@"
