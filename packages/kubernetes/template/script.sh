#!/bin/bash

set -euo pipefail

# Populate VERSIONS array latest kURL-support versions (1.21, 1.22, 1.23, 1.24) available
VERSIONS=()
function find_available_versions() {
    docker build -t k8s - < Dockerfile

    local versions127=($(docker run k8s apt list -a kubelet 2>/dev/null | grep -Eo '1\.27\.[0-9]+' | sort -rV | uniq))
    if [ ${#versions127[@]} -gt 0 ]; then
        echo "Found latest version for Kubernetes 1.27: ${versions127[0]}"
        VERSIONS+=("${versions127[0]}")
    fi

    local versions126=($(docker run k8s apt list -a kubelet 2>/dev/null | grep -Eo '1\.26\.[0-9]+' | sort -rV | uniq))
    if [ ${#versions126[@]} -gt 0 ]; then
        echo "Found latest version for Kubernetes 1.26: ${versions126[0]}"
        VERSIONS+=("${versions126[0]}")
    fi

    local versions125=($(docker run k8s apt list -a kubelet 2>/dev/null | grep -Eo '1\.25\.[0-9]+' | sort -rV | uniq))
    if [ ${#versions125[@]} -gt 0 ]; then
        echo "Found latest version for Kubernetes 1.25: ${versions125[0]}"
        VERSIONS+=("${versions125[0]}")
    fi

    local versions124=($(docker run k8s apt list -a kubelet 2>/dev/null | grep -Eo '1\.24\.[0-9]+' | sort -rV | uniq))
    if [ ${#versions124[@]} -gt 0 ]; then
        echo "Found latest version for Kubernetes 1.24: ${versions124[0]}"
        VERSIONS+=("${versions124[0]}")
    fi

    local versions123=($(docker run k8s apt list -a kubelet 2>/dev/null | grep -Eo '1\.23\.[0-9]+' | sort -rV | uniq))
    if [ ${#versions123[@]} -gt 0 ]; then
        echo "Found latest version for Kubernetes 1.23: ${versions123[0]}"
        VERSIONS+=("${versions123[0]}")
    fi

    local versions122=($(docker run k8s apt list -a kubelet 2>/dev/null | grep -Eo '1\.22\.[0-9]+' | sort -rV | uniq))
    if [ ${#versions122[@]} -gt 0 ]; then
        echo "Found latest version for Kubernetes 1.22: ${versions122[0]}"
        VERSIONS+=("${versions122[0]}")
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

    local minor=$(echo "$version" | awk -F'.' '{ print $2 }')
    local criToolsVersion=$(curl -H "Authorization: token ${GITHUB_TOKEN}" -s https://api.github.com/repos/kubernetes-sigs/cri-tools/releases | \
        grep '"tag_name": ' | \
        ( grep -Eo "1\.${minor}\.[0-9]+" || true ) | \
        head -1)

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
    # TODO: in the future change this image to registry.k8s.io
    echo "image conformance k8s.gcr.io/conformance:v${version}" > "../$version/conformance/Manifest"


    # --mode quick image
    local image="$(docker run --rm --entrypoint e2e.test "k8s.gcr.io/conformance:v${version}" --list-images | grep "nginx" | sort -n | head -n 1)"
    local name="$(echo "$image" | awk -F'[/:]' '{ i = 2; for (--i; i >= 0; i--){ printf "%s-",$(NF-i)} print "" }' | sed 's/\./-/' | sed 's/-$//')"
    echo "image $name $image" >> "../$version/conformance/Manifest"

    # The following code will add all conformance images to manifest but it adds too much to the bundle

    # sonobuoy_pull_images "$version" || true

    # local image=
    # for image in $(docker run --rm --entrypoint e2e.test "k8s.gcr.io/conformance:v${version}" --list-images) ; do
    #     if docker inspect "$image" >/dev/null 2>&1 ; then
    #         local name="$(echo "$image" | awk -F'[/:]' '{ i = 2; for (--i; i >= 0; i--){ printf "%s-",$(NF-i)} print "" }' | sed 's/\./-/' | sed 's/-$//')"
    #         echo "image $name $image" >> "../$version/conformance/Manifest"
    #     fi
    # done
}

function sonobuoy_pull_images() {
    local version="$1"
    local tmpdir="$(mktemp -d)"
    download_sonobuoy "$tmpdir"

    "${tmpdir}/sonobuoy" images pull --kubernetes-version "v${version}"
}

function download_sonobuoy() {
    local tmpdir="$1"
    local sonobuoy_version="$(get_latest_sonobuoy_release_version)"
    curl -sL -o "${tmpdir}/sonobuoy.tar.gz" https://github.com/vmware-tanzu/sonobuoy/releases/download/v${sonobuoy_version}/sonobuoy_${sonobuoy_version}_linux_amd64.tar.gz && \
        tar xzf "${tmpdir}/sonobuoy.tar.gz" -C "${tmpdir}"
}

function get_latest_sonobuoy_release_version() {
    curl -sI https://github.com/vmware-tanzu/sonobuoy/releases/latest | \
        grep -i "^location" | \
        grep -Eo "0\.[0-9]+\.[0-9]+"
}

function update_available_versions() {
    local version127=( $( for i in "${VERSIONS[@]}" ; do echo $i ; done | grep '^1.27' ) )
    if [ ${#version127[@]} -gt 0 ]; then
        if ! sed '0,/cron-kubernetes-update-127/d' ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -q "${version127[0]}" ; then
            sed -i "/cron-kubernetes-update-127/a\    \"${version127[0]}\"\," ../../../web/src/installers/versions.js
        fi
    fi

    local version126=( $( for i in "${VERSIONS[@]}" ; do echo $i ; done | grep '^1.26' ) )
    if [ ${#version126[@]} -gt 0 ]; then
        if ! sed '0,/cron-kubernetes-update-126/d' ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -q "${version126[0]}" ; then
            sed -i "/cron-kubernetes-update-126/a\    \"${version126[0]}\"\," ../../../web/src/installers/versions.js
        fi
    fi

    local version125=( $( for i in "${VERSIONS[@]}" ; do echo $i ; done | grep '^1.25' ) )
    if [ ${#version125[@]} -gt 0 ]; then
        if ! sed '0,/cron-kubernetes-update-125/d' ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -q "${version125[0]}" ; then
            sed -i "/cron-kubernetes-update-125/a\    \"${version125[0]}\"\," ../../../web/src/installers/versions.js
        fi
    fi

    local version124=( $( for i in "${VERSIONS[@]}" ; do echo $i ; done | grep '^1.24' ) )
    if [ ${#version124[@]} -gt 0 ]; then
        if ! sed '0,/cron-kubernetes-update-124/d' ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -q "${version124[0]}" ; then
            sed -i "/cron-kubernetes-update-124/a\    \"${version124[0]}\"\," ../../../web/src/installers/versions.js
        fi
    fi

    local version123=( $( for i in "${VERSIONS[@]}" ; do echo $i ; done | grep '^1.23' ) )
    if [ ${#version123[@]} -gt 0 ]; then
        if ! sed '0,/cron-kubernetes-update-123/d' ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -q "${version123[0]}" ; then
            sed -i "/cron-kubernetes-update-123/a\    \"${version123[0]}\"\," ../../../web/src/installers/versions.js
        fi
    fi

    local version122=( $( for i in "${VERSIONS[@]}" ; do echo $i ; done | grep '^1.22' ) )
    if [ ${#version122[@]} -gt 0 ]; then
        if ! sed '0,/cron-kubernetes-update-122/d' ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -q "${version122[0]}" ; then
            sed -i "/cron-kubernetes-update-122/a\    \"${version122[0]}\"\," ../../../web/src/installers/versions.js
        fi
    fi
}

function generate_step_versions() {
    local steps=()
    local version=
    local max_minor=0
    while read -r version; do
        if ! echo "$version" | grep -Eq '[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+' ; then
            continue
        fi
        local step_minor=
        step_minor="$(echo "$version" | cut -d. -f2)"
        steps[$step_minor]="$version"
        ((step_minor > max_minor)) && max_minor="$step_minor"
    done <<< "$(find ../ -maxdepth 1 -type d -printf '%P\n' | sort -V)"
    for (( version=0; version <= max_minor; version++ )); do
        [ "${steps[version]+abc}" ] && continue
        steps[$version]="0.0.0"
    done

    sed -i 's|^STEP_VERSIONS=(.*|STEP_VERSIONS=('"${steps[*]}"')|' ../../../hack/testdata/manifest/clean
    sed -i 's|^STEP_VERSIONS=(.*|STEP_VERSIONS=('"${steps[*]}"')|' ../../../scripts/Manifest
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

    generate_step_versions
}

main "$@"
