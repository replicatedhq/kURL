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

function init_manifest_file() {
    mkdir -p /tmp/containerd/$version
    local file=/tmp/containerd/$version/Manifest

    cat <<EOT >> $file
yum libzstd
asset runc https://github.com/opencontainers/runc/releases/download/v1.0.0-rc95/runc.amd64
EOT
}

function add_supported_os_to_manifest_file() {
    local version=$1
    local os=$2
    local dockerfile=$3
    local file=/tmp/containerd/$version/Manifest

    cat <<EOT >> $file
dockerout $os addons/containerd/template/$dockerfile $version
EOT
}

function init_preflight_file() {
    local version=$1

    mkdir -p /tmp/containerd/$version
    local file=/tmp/containerd/$version/host-preflight.yaml

    cat <<EOT > $file
apiVersion: troubleshoot.sh/v1beta2
kind: HostPreflight
metadata:
  name: kurl-builtin
spec:
  collectors:
    - hostOS: {}
  analyzers:
    - hostOS:
        outcomes:
EOT
}

function add_unsupported_os_to_preflight_file() {
    local version=$1
    local os_distro=$2
    local os_version=$3

    local file=/tmp/containerd/$version/host-preflight.yaml
    cat <<EOT >> $file
          - fail:
              when: "$os_distro = $os_version"
              message: "containerd addon does not support $os_distro $os_version"
EOT
}

function add_supported_os_to_preflight_file() {
    local version=$1
    local os_distro=$2
    local os_version=$3

    local file=/tmp/containerd/$version/host-preflight.yaml
    cat <<EOT >> $file
          - pass:
              when: "$os_distro = $os_version"
              message: "containerd addon supports $os_distro $os_version"
EOT
}

function copy_generated_files() {
    local version=$1

    local src=/tmp/containerd/$version/host-preflight.yaml
    local dst=../$version/host-preflight.yaml

    if [ -f $src ]; then
        mv -f $src $dst
    fi

    local src=/tmp/containerd/$version/Manifest
    local dst=../$version/Manifest

    if [ -f $src ]; then
        mv -f $src $dst
    fi
}

VERSIONS=()
function find_common_versions() {
    docker build -t centos7 -f Dockerfile.centos7 .
    docker build -t centos8 -f Dockerfile.centos8 .
    docker build -t ubuntu16 -f Dockerfile.ubuntu16 .
    docker build -t ubuntu18 -f Dockerfile.ubuntu18 .
    docker build -t ubuntu20 -f Dockerfile.ubuntu20 .

    CENTOS7_VERSIONS=($(docker run --rm -i centos7 yum list --showduplicates containerd.io | grep -Eo '1\.[[:digit:]]+\.[[:digit:]]+' | grep -vE '1\.[012]\.' | sort -rV | uniq))
    echo "Found ${#CENTOS7_VERSIONS[*]} containerd versions for CentOS 7: ${CENTOS7_VERSIONS[*]}"

    CENTOS8_VERSIONS=($(docker run --rm -i centos8 yum list --showduplicates containerd.io | grep -Eo '1\.[[:digit:]]+\.[[:digit:]]+' | grep -vE '1\.[012]\.' | sort -rV | uniq))
    echo "Found ${#CENTOS8_VERSIONS[*]} containerd versions for CentOS 8: ${CENTOS8_VERSIONS[*]}"

    UBUNTU16_VERSIONS=($(docker run --rm -i ubuntu16 apt-cache madison containerd.io | grep -Eo '1\.[[:digit:]]+\.[[:digit:]]+' | grep -vE '1\.[012]\.' | sort -rV | uniq))
    echo "Found ${#UBUNTU16_VERSIONS[*]} containerd versions for Ubuntu 16: ${UBUNTU16_VERSIONS[*]}"

    UBUNTU18_VERSIONS=($(docker run --rm -i ubuntu18 apt-cache madison containerd.io | grep -Eo '1\.[[:digit:]]+\.[[:digit:]]+' | grep -vE '1\.[012]\.' | sort -rV | uniq))
    echo "Found ${#UBUNTU18_VERSIONS[*]} containerd versions for Ubuntu 18: ${UBUNTU18_VERSIONS[*]}"

    UBUNTU20_VERSIONS=($(docker run --rm -i ubuntu20 apt-cache madison containerd.io | grep -Eo '1\.[[:digit:]]+\.[[:digit:]]+' | grep -vE '1\.[012]\.' | sort -rV | uniq))
    echo "Found ${#UBUNTU20_VERSIONS[*]} containerd versions for Ubuntu 20: ${UBUNTU20_VERSIONS[*]}"

    # Get the intersection of versions available for all operating systems
    local ALL_VERSIONS=("${CENTOS7_VERSIONS[@]}" "${CENTOS8_VERSIONS[@]}" "${UBUNTU16_VERSIONS[@]}" "${UBUNTU18_VERSIONS[@]}" "${UBUNTU20_VERSIONS[@]}")
    ALL_VERSIONS=($(echo "${ALL_VERSIONS[@]}" | tr ' ' '\n' | sort -rV | uniq -d | tr '\n' ' ')) # remove duplicates

    for version in ${ALL_VERSIONS[@]}; do
        init_preflight_file $version
        init_manifest_file $version

        if ! contains "$version" ${CENTOS7_VERSIONS[*]}; then
            echo "CentOS 7 lacks version $version"
            add_unsupported_os_to_preflight_file $version "centos" "7"
        else
            add_supported_os_to_preflight_file $version "centos" "7"
            add_supported_os_to_manifest_file $version "rhel-7" "Dockerfile.centos7"
            add_supported_os_to_manifest_file $version "rhel-7-force" "Dockerfile.centos7-force"
        fi

        if ! contains "$version" ${CENTOS8_VERSIONS[*]}; then
            echo "CentOS 8 lacks version $version"
            add_unsupported_os_to_preflight_file $version "centos" "8"
        else
            add_supported_os_to_preflight_file $version "centos" "8"
            add_supported_os_to_manifest_file $version "rhel-8" "Dockerfile.centos8"
        fi

        if ! contains "$version" ${UBUNTU16_VERSIONS[*]}; then
            echo "Ubuntu 16 lacks version $version"
            add_unsupported_os_to_preflight_file $version "ubuntu" "16.04"
        else
            add_supported_os_to_preflight_file $version "ubuntu" "16.04"
            add_supported_os_to_manifest_file $version "ubuntu-16.04" "Dockerfile.ubuntu16"
        fi

        if ! contains "$version" ${UBUNTU18_VERSIONS[*]}; then
            echo "Ubuntu 18 lacks version $version"
            add_unsupported_os_to_preflight_file $version "ubuntu" "18.04"
        else
            add_supported_os_to_preflight_file $version "ubuntu" "18.04"
            add_supported_os_to_manifest_file $version "ubuntu-18.04" "Dockerfile.ubuntu18"
        fi

        if ! contains "$version" ${UBUNTU20_VERSIONS[*]}; then
            echo "Ubuntu 20 lacks version $version"
            add_unsupported_os_to_preflight_file $version "ubuntu" "20.04"
        else
            add_supported_os_to_preflight_file $version "ubuntu" "20.04"
            add_supported_os_to_manifest_file $version "ubuntu-20.04" "Dockerfile.ubuntu20"
        fi

        VERSIONS+=("$version")
    done

    echo "Found ${#VERSIONS[*]} containerd versions >=1.3 available for all operating systems: ${VERSIONS[*]}"

    VERSIONS+=("1.2.13")

    export GREATEST_VERSION="${VERSIONS[0]}"

    # Move 1.6.x to the back so it's not the latest
    local V6=()
    for v in ${VERSIONS[@]}; do
        if [[ $v == 1\.6\.* ]]; then
            VERSIONS=("${VERSIONS[@]/$v}")
            V6+=("${v}")
        fi
    done
    VERSIONS=("${VERSIONS[@]}" "${V6[@]}")
}

function generate_version() {
    mkdir -p "../$version"
    cp -r ./base/* "../$version"

    sed -i "s/__version__/$version/g" "../$version/install.sh"

    copy_generated_files $version

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
    sed -i "/cron-containerd-update/c\  containerd: [${v}], \/\/ cron-containerd-update" ../../../web/src/installers/versions.js
}

function main() {
    find_common_versions

    for version in ${VERSIONS[*]}; do
        if [ "$version" != "1.2.13" ]; then
            generate_version "$version"
        fi
    done

    echo "::set-output name=containerd_version::$GREATEST_VERSION"

    update_available_versions
}

main
