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
yum container-selinux
EOT
    # Note that containerd requires runc and each release officially uses one specific version in their
    # tests. Therefore, that is the version of runc which is supported and should be used by each
    # respective containerd release. More info: https://github.com/containerd/containerd/blob/main/docs/RUNC.md
    if echo "$version" | grep -qF "1.2."; then
        # See the runc version used to test the releases 1.2:https://github.com/containerd/containerd/blob/release/1.2/vendor.conf#L23
        echo "asset runc https://github.com/opencontainers/runc/releases/download/v1.0.0-rc10/runc.amd64" >> $file
    elif echo "$version" | grep -qF "1.3."; then
        # See the runc version used to test the releases 1.3:https://github.com/containerd/containerd/blob/release/1.3/vendor.conf#L33
        echo "asset runc https://github.com/opencontainers/runc/releases/download/v1.0.0-rc10/runc.amd64" >> $file
    elif echo "$version" | grep -qF "1.4."; then
        # See the runc version used to test the releases 1.4:https://github.com/containerd/containerd/blob/release/1.4/script/setup/runc-version
        echo "asset runc https://github.com/opencontainers/runc/releases/download/v1.0.3/runc.amd64" >> $file
    else
        # detect runc version from upstream project used to test the containerd release
        local runc_version="$(curl -sSL https://raw.githubusercontent.com/containerd/containerd/release/"$(echo "$version" | grep -Eo '[[:digit:]]\.[[:digit:]]+')"/script/setup/runc-version)"
        if [ -z "$runc_version" ]; then
            echo "Failed to detect runc version"
            exit 1
        fi
        echo "asset runc https://github.com/opencontainers/runc/releases/download/$runc_version/runc.amd64" >> $file
    fi
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

function add_override_os_to_manifest_file() {
    local version=$1
    local override_version=$2
    local os=$3
    local dockerfile=$4
    local file=/tmp/containerd/$version/Manifest

    cat <<EOT >> $file
dockerout $os addons/containerd/template/$dockerfile $override_version
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

function add_override_os_to_preflight_file() {
    local version=$1
    local replacement_version=$2
    local os_distro=$3
    local os_version=$4

    local file=/tmp/containerd/$version/host-preflight.yaml
    cat <<EOT >> $file
          - warn:
              when: "$os_distro = $os_version"
              message: "containerd addon supports $os_distro $os_version, but only up to containerd $replacement_version, which will be installed instead of $version"
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

UNSUPPORTED_CONTAINERD_MINORS="01234"

VERSIONS=()
function find_common_versions() {
    docker build --no-cache --pull -t centos7 -f Dockerfile.centos7 .
    docker build --no-cache --pull -t centos8 -f Dockerfile.centos8 .
    docker build --no-cache --pull -t rhel9 -f Dockerfile.rhel9 .
    docker build --no-cache --pull -t ubuntu16 -f Dockerfile.ubuntu16 .
    docker build --no-cache --pull -t ubuntu18 -f Dockerfile.ubuntu18 .
    docker build --no-cache --pull -t ubuntu20 -f Dockerfile.ubuntu20 .
    docker build --no-cache --pull -t ubuntu22 -f Dockerfile.ubuntu22 .

    CENTOS7_VERSIONS=($(docker run --rm -i centos7 yum list --showduplicates containerd.io | grep -Eo '1\.[[:digit:]]+\.[[:digit:]]+' | grep -vE '1\.['"$UNSUPPORTED_CONTAINERD_MINORS"']\.' | sort -rV | uniq))
    echo "Found ${#CENTOS7_VERSIONS[*]} containerd versions for CentOS 7: ${CENTOS7_VERSIONS[*]}"

    CENTOS8_VERSIONS=($(docker run --rm -i centos8 yum list --showduplicates containerd.io | grep -Eo '1\.[[:digit:]]+\.[[:digit:]]+' | grep -vE '1\.['"$UNSUPPORTED_CONTAINERD_MINORS"']\.' | sort -rV | uniq))
    echo "Found ${#CENTOS8_VERSIONS[*]} containerd versions for CentOS 8: ${CENTOS8_VERSIONS[*]}"

    RHEL9_VERSIONS=($(docker run --rm -i rhel9 yum list --showduplicates containerd.io | grep -Eo '1\.[[:digit:]]+\.[[:digit:]]+' | grep -vE '1\.['"$UNSUPPORTED_CONTAINERD_MINORS"']\.' | sort -rV | uniq))
    echo "Found ${#RHEL9_VERSIONS[*]} containerd versions for RHEL 9: ${RHEL9_VERSIONS[*]}"

    UBUNTU16_VERSIONS=($(docker run --rm -i ubuntu16 apt-cache madison containerd.io | grep -Eo '1\.[[:digit:]]+\.[[:digit:]]+' | grep -vE '1\.['"$UNSUPPORTED_CONTAINERD_MINORS"']\.' | sort -rV | uniq || true)) # no supported versions
    echo "Found ${#UBUNTU16_VERSIONS[*]} containerd versions for Ubuntu 16: ${UBUNTU16_VERSIONS[*]}"

    UBUNTU18_VERSIONS=($(docker run --rm -i ubuntu18 apt-cache madison containerd.io | grep -Eo '1\.[[:digit:]]+\.[[:digit:]]+' | grep -vE '1\.['"$UNSUPPORTED_CONTAINERD_MINORS"']\.' | sort -rV | uniq))
    echo "Found ${#UBUNTU18_VERSIONS[*]} containerd versions for Ubuntu 18: ${UBUNTU18_VERSIONS[*]}"

    UBUNTU20_VERSIONS=($(docker run --rm -i ubuntu20 apt-cache madison containerd.io | grep -Eo '1\.[[:digit:]]+\.[[:digit:]]+' | grep -vE '1\.['"$UNSUPPORTED_CONTAINERD_MINORS"']\.' | sort -rV | uniq))
    echo "Found ${#UBUNTU20_VERSIONS[*]} containerd versions for Ubuntu 20: ${UBUNTU20_VERSIONS[*]}"

    UBUNTU22_VERSIONS=($(docker run --rm -i ubuntu22 apt-cache madison containerd.io | grep -Eo '1\.[[:digit:]]+\.[[:digit:]]+' | grep -vE '1\.['"$UNSUPPORTED_CONTAINERD_MINORS"']\.' | sort -rV | uniq))
    echo "Found ${#UBUNTU22_VERSIONS[*]} containerd versions for Ubuntu 22: ${UBUNTU22_VERSIONS[*]}"

    # Get the union of versions available for all operating systems
    local ALL_VERSIONS=("${CENTOS7_VERSIONS[@]}" "${CENTOS8_VERSIONS[@]}" "${RHEL9_VERSIONS[@]}" "${UBUNTU16_VERSIONS[@]}" "${UBUNTU18_VERSIONS[@]}" "${UBUNTU20_VERSIONS[@]}" "${UBUNTU22_VERSIONS[@]}")
    ALL_VERSIONS=($(echo "${ALL_VERSIONS[@]}" | tr ' ' '\n' | sort -rV | uniq -d | tr '\n' ' ')) # remove duplicates
    ALL_VERSIONS=($(echo "${ALL_VERSIONS[@]}" | tr ' ' '\n' | grep -vE '1\.7\.' | tr '\n' ' ')) # remove 7.x versions

    for version in ${ALL_VERSIONS[@]}; do
        init_preflight_file $version
        init_manifest_file $version

        if ! contains "$version" ${CENTOS7_VERSIONS[*]}; then
            echo "Centos 7 lacks version $version, using ${CENTOS7_VERSIONS[0]} instead"
            add_override_os_to_preflight_file "$version" "${CENTOS7_VERSIONS[0]}" "centos" "7"
            add_override_os_to_preflight_file "$version" "${CENTOS7_VERSIONS[0]}" "rhel" "7"
            add_override_os_to_preflight_file "$version" "${CENTOS7_VERSIONS[0]}" "ol" "7"
            add_override_os_to_manifest_file "$version" "${CENTOS7_VERSIONS[0]}" "rhel-7" "Dockerfile.centos7"
            add_override_os_to_manifest_file "$version" "${CENTOS7_VERSIONS[0]}" "rhel-7-force" "Dockerfile.centos7-force"
        else
            add_supported_os_to_preflight_file "$version" "centos" "7"
            add_supported_os_to_preflight_file "$version" "rhel" "7"
            add_supported_os_to_preflight_file "$version" "ol" "7"
            add_supported_os_to_manifest_file "$version" "rhel-7" "Dockerfile.centos7"
            add_supported_os_to_manifest_file "$version" "rhel-7-force" "Dockerfile.centos7-force"
        fi

        if ! contains "$version" ${CENTOS8_VERSIONS[*]}; then
            echo "Rocky 8 lacks version $version, using ${CENTOS8_VERSIONS[0]} instead"
            add_override_os_to_preflight_file "$version" "${CENTOS8_VERSIONS[0]}" "centos" "8"
            add_override_os_to_preflight_file "$version" "${CENTOS8_VERSIONS[0]}" "rhel" "8"
            add_override_os_to_preflight_file "$version" "${CENTOS8_VERSIONS[0]}" "ol" "8"
            add_override_os_to_manifest_file "$version" "${CENTOS8_VERSIONS[0]}" "rhel-8" "Dockerfile.centos8"
        else
            add_supported_os_to_preflight_file "$version" "centos" "8"
            add_supported_os_to_preflight_file "$version" "rhel" "8"
            add_supported_os_to_preflight_file "$version" "ol" "8"
            add_supported_os_to_manifest_file "$version" "rhel-8" "Dockerfile.centos8"
        fi

        if ! contains "$version" ${RHEL9_VERSIONS[*]}; then
            echo "RHEL 9 lacks version $version"
            add_unsupported_os_to_preflight_file "$version" "centos" "9"
            add_unsupported_os_to_preflight_file "$version" "rhel" "9"
            add_unsupported_os_to_preflight_file "$version" "ol" "9"
            add_unsupported_os_to_preflight_file "$version" "rocky" "9"
        else
            add_supported_os_to_preflight_file "$version" "centos" "9"
            add_supported_os_to_preflight_file "$version" "rhel" "9"
            add_supported_os_to_preflight_file "$version" "rocky" "9"
            add_supported_os_to_manifest_file "$version" "rhel-9" "Dockerfile.rhel9"

            # exclude Oracle Linux 9 (OL 9) until we officially support it
            add_unsupported_os_to_preflight_file "$version" "ol" "9"
        fi

        if ! contains "$version" ${UBUNTU16_VERSIONS[*]}; then
            echo "Ubuntu 16 lacks version $version"
            add_unsupported_os_to_preflight_file "$version" "ubuntu" "16.04"
        else
            add_supported_os_to_preflight_file "$version" "ubuntu" "16.04"
            add_supported_os_to_manifest_file "$version" "ubuntu-16.04" "Dockerfile.ubuntu16"
        fi

        if ! contains "$version" ${UBUNTU18_VERSIONS[*]}; then
            echo "Ubuntu 18 lacks version $version, using ${UBUNTU18_VERSIONS[0]} instead"
            add_override_os_to_preflight_file "$version" "${UBUNTU18_VERSIONS[0]}" "ubuntu" "18.04"
            add_override_os_to_manifest_file "$version" "${UBUNTU18_VERSIONS[0]}" "ubuntu-18.04" "Dockerfile.ubuntu18"
        else
            add_supported_os_to_preflight_file "$version" "ubuntu" "18.04"
            add_supported_os_to_manifest_file "$version" "ubuntu-18.04" "Dockerfile.ubuntu18"
        fi

        if ! contains "$version" ${UBUNTU20_VERSIONS[*]}; then
            echo "Ubuntu 20 lacks version $version"
            add_unsupported_os_to_preflight_file "$version" "ubuntu" "20.04"
        else
            add_supported_os_to_preflight_file "$version" "ubuntu" "20.04"
            add_supported_os_to_manifest_file "$version" "ubuntu-20.04" "Dockerfile.ubuntu20"
        fi

        if ! contains "$version" ${UBUNTU22_VERSIONS[*]}; then
            echo "Ubuntu 22 lacks version $version"
            add_unsupported_os_to_preflight_file "$version" "ubuntu" "22.04"
        else
            add_supported_os_to_preflight_file "$version" "ubuntu" "22.04"
            add_supported_os_to_manifest_file "$version" "ubuntu-22.04" "Dockerfile.ubuntu22"
        fi

        VERSIONS+=("$version")
    done

    echo "Found ${#VERSIONS[*]} containerd versions >=1.3 available for at least one operating system: ${VERSIONS[*]}"

    export GREATEST_VERSION="${VERSIONS[0]}"
}

function find_pause_image() {
    # The Kubernetes airgap package only includes the default pause image specified by kubeadm for the
    # version, so the correct pause image used by containerd must be included in its bundle.

    local pause_image=
    pause_image="$(docker run --rm -i ubuntu20 sh -c \
        "apt-cache madison containerd.io | grep -F ""$version"" | sed 's/|//g' | awk '{ print \$2 }' | \
        xargs -I{} apt-get install -y -qq containerd.io={} >/dev/null 2>&1 && \
        containerd config default | grep sandbox_image | sed 's/[=\"]//g' | awk '{ print \$2 }'")"
    if [ -n "$pause_image" ]; then
        echo "$pause_image"
        return
    fi

    # fallback
    if echo "$version" | grep -qE "1\.3\."; then
        echo "k8s.gcr.io/pause:3.1"
    elif echo "$version" | grep -qE "1\.4\."; then
        echo "k8s.gcr.io/pause:3.2"
    elif echo "$version" | grep -qE "1\.5\."; then
        echo "k8s.gcr.io/pause:3.5"
    else
        echo "k8s.gcr.io/pause:3.6"
    fi
}

function generate_version() {
    mkdir -p "../$version"
    cp -r ./base/* "../$version"

    sed -i "s/__version__/$version/g" "../$version/install.sh"

    copy_generated_files $version

    echo "image pause $(find_pause_image)" >> "../$version/Manifest"
}

function update_available_versions() {
    local v=""
    for version in ${VERSIONS[@]}; do
        v="${v}\"${version}\", "
    done
    sed -i "/cron-containerd-update/c\    ${v}\/\/ cron-containerd-update" ../../../web/src/installers/versions.js
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
    sed -i 's|^CONTAINERD_STEP_VERSIONS=(.*|CONTAINERD_STEP_VERSIONS=('"${steps[*]}"')|' ../../../hack/testdata/manifest/clean
    sed -i 's|^CONTAINERD_STEP_VERSIONS=(.*|CONTAINERD_STEP_VERSIONS=('"${steps[*]}"')|' ../../../scripts/Manifest
}

function main() {
    find_common_versions

    for version in ${VERSIONS[*]}; do
        if [ "$version" != "1.2.13" ]; then
            generate_version "$version"
        fi
    done

    echo "containerd_version=$GREATEST_VERSION" >> "$GITHUB_OUTPUT"

    update_available_versions
    generate_step_versions
}

main
