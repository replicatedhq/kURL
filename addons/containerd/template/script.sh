#!/bin/bash

set -euo pipefail

function contains() {
    local value=$1
    shift
    local array="$@"

    echo "${array[*]}"

    for element in ${array[@]}; do
        if [ "$element" = "$value" ]; then
            return 0
        fi
    done

    return 1
}


VERSIONS=()
function find_common_versions() {
    docker build -t centos7 -f Dockerfile.centos7 .
    docker build -t centos8 -f Dockerfile.centos8 .
    docker build -t ubuntu16 -f Dockerfile.ubuntu16 .
    docker build -t ubuntu18 -f Dockerfile.ubuntu18 .
    docker build -t ubuntu20 -f Dockerfile.ubuntu20 .

    CENTOS7_VERSIONS=($(docker run --rm -i centos7 yum list --showduplicates containerd.io | grep -Eo '1\.[[:digit:]]+\.[[:digit:]]+' | grep -vE '1\.[012]\.' | sort -r | uniq))
    echo "Found ${#CENTOS7_VERSIONS[*]} containerd versions for CentOS 7: ${CENTOS7_VERSIONS[*]}"

    CENTOS8_VERSIONS=($(docker run --rm -i centos8 yum list --showduplicates containerd.io | grep -Eo '1\.[[:digit:]]+\.[[:digit:]]+' | grep -vE '1\.[012]\.' | sort -r | uniq))
    echo "Found ${#CENTOS8_VERSIONS[*]} containerd versions for CentOS 8: ${CENTOS8_VERSIONS[*]}"

    UBUNTU16_VERSIONS=($(docker run --rm -i ubuntu16 apt-cache madison containerd.io | grep -Eo '1\.[[:digit:]]+\.[[:digit:]]+' | grep -vE '1\.[012]\.' | sort -r | uniq))
    echo "Found ${#UBUNTU16_VERSIONS[*]} containerd versions for Ubuntu 16: ${UBUNTU16_VERSIONS[*]}"

    UBUNTU18_VERSIONS=($(docker run --rm -i ubuntu18 apt-cache madison containerd.io | grep -Eo '1\.[[:digit:]]+\.[[:digit:]]+' | grep -vE '1\.[012]\.' | sort -r | uniq))
    echo "Found ${#UBUNTU18_VERSIONS[*]} containerd versions for Ubuntu 18: ${UBUNTU18_VERSIONS[*]}"

    UBUNTU20_VERSIONS=($(docker run --rm -i ubuntu20 apt-cache madison containerd.io | grep -Eo '1\.[[:digit:]]+\.[[:digit:]]+' | grep -vE '1\.[012]\.' | sort -r | uniq))
    echo "Found ${#UBUNTU20_VERSIONS[*]} containerd versions for Ubuntu 20: ${UBUNTU20_VERSIONS[*]}"

    # Get the intersection of versions available for all operating systems
    for version in ${CENTOS7_VERSIONS[@]}; do
        if ! contains "$version" ${CENTOS8_VERSIONS[*]}; then
            echo "CentOS 8 lacks version $version"
            continue
        fi
        if ! contains "$version" ${UBUNTU16_VERSIONS[*]}; then
            echo "Ubuntu 16 lacks version $version"
            continue
        fi
        if ! contains "$version" ${UBUNTU18_VERSIONS[*]}; then
            echo "Ubuntu 18 lacks version $version"
            continue
        fi
        if ! contains "$version" ${UBUNTU20_VERSIONS[*]}; then
            echo "Ubuntu 20 lacks version $version"
            continue
        fi
        VERSIONS+=("$version")
    done

    echo "Found ${#VERSIONS[*]} containerd versions >=1.3 available for all operating systems: ${VERSIONS[*]}"
}

function generate_version() {
    mkdir -p "../$version"
    cp -r ./base/* "../$version"

    sed -i "s/__version__/$version/g" "../$version/Manifest"

    # Containerd overrides the pod sandbox image with pause:3.1 for 1.3.x and pause:3.2 for 1.4+.
    # The Kubernetes airgap package only includes the default pause image specified by kubeadm for the
    # version, so the correct pause image used by containerd must be included in its bundle.
    if echo "$version" | grep -qE "1\.3\."; then
        echo "image pause k8s.gcr.io/pause:3.1" >> "../$version/Manifest"
    else
        echo "image pause k8s.gcr.io/pause:3.2" >> "../$version/Manifest"
    fi
}

function update_available_versions() {
    local v=""
    for version in ${VERSIONS[@]}; do
        v="${v}\"${version}\", "
    done
    sed -i "/cron-containerd-update/c\    containerd: [${v}\"1.2.13\"], \/\/ cron-containerd-update" ../../../web/src/installers/index.ts
}

function main() {
    find_common_versions

    for version in ${VERSIONS[*]}; do
        generate_version "$version"
    done

    echo "::set-output name=containerd_version::$VERSIONS"    

    update_available_versions
}

main
