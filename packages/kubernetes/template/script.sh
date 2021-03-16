#!/bin/bash

set -euo pipefail

# Populate VERSIONS array with 1.20+ versions available
VERSIONS=()
function find_available_versions() {
    docker build -t k8s - < Dockerfile
    VERSIONS=($(docker run k8s apt list -a kubelet 2>/dev/null | grep -Eo '1\.[2-9][0-9]\.[0-9]+' | sort -rV | uniq))

    echo "Found ${#VERSIONS[*]} versions for Kubernetes 1.20+: ${VERSIONS[*]}"
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

    local criToolsVersion=$(curl -Ls -m 60 -o /dev/null -w %{url_effective} https://github.com/kubernetes-sigs/cri-tools/releases/latest | xargs basename)

    echo "" >> "../$version/Manifest"
    echo "asset kubeadm https://storage.googleapis.com/kubernetes-release/release/v$version/bin/linux/amd64/kubeadm" >> "../$version/Manifest"
    echo "asset crictl-linux-amd64.tar.gz https://github.com/kubernetes-sigs/cri-tools/releases/download/$criToolsVersion/crictl-$criToolsVersion-linux-amd64.tar.gz" >> "../$version/Manifest"

    echo "" >> "../$version/Manifest"
    echo "asset kustomize-v2.0.3 https://github.com/kubernetes-sigs/kustomize/releases/download/v2.0.3/kustomize_2.0.3_linux_amd64" >> "../$version/Manifest"
    echo "asset kustomize-v3.5.4.tar.gz https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv3.5.4/kustomize_v3.5.4_linux_amd64.tar.gz" >> "../$version/Manifest"
}

function update_available_versions() {
    sed -i "/cron-kubernetes-update/c\      \"$(echo ${VERSIONS[*]} | sed 's/ /", "/g')\", \/\/ cron-kubernetes-update" ../../../web/src/installers/index.ts
}

function main() {
    find_available_versions

    for version in ${VERSIONS[*]}; do
        generate_version_directory "$version"
    done
    echo "::set-output name=kubernetes_version::$VERSIONS"    

    update_available_versions
}

main
