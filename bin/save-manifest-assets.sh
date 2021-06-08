#!/bin/bash

set -e

PACKAGE_NAME=$1
MANIFEST_PATH=$2
OUT_DIR=$3

mkdir -p "$OUT_DIR"

function build_rhel_7() {
    local packages=("$@")
    local outdir="${OUT_DIR}/rhel-7"

    mkdir -p "${outdir}"

    docker rm -f "rhel-7-${PACKAGE_NAME}" 2>/dev/null || true
    # Use the oldest OS minor version supported to ensure that updates required for outdated
    # packages are included.
    docker run \
        --name "rhel-7-${PACKAGE_NAME}" \
        centos:7.4.1708 \
        /bin/bash -c "\
            set -x
            yum install -y epel-release && \
            mkdir -p /packages/archives && \
            yumdownloader --installroot=/tmp/empty-directory --releasever=/ --resolve --destdir=/packages/archives -y ${packages[*]}"
    sudo docker cp "rhel-7-${PACKAGE_NAME}":/packages/archives "${outdir}"
    sudo chown -R $UID "${outdir}"
}

function createrepo_rhel_7() {
    local outdir=
    outdir="$(realpath "${OUT_DIR}")/rhel-7"

    docker rm -f "rhel-7-createrepo-${PACKAGE_NAME}" 2>/dev/null || true
    # Use the oldest OS minor version supported to ensure that updates required for outdated
    # packages are included.
    docker run \
        --name "rhel-7-createrepo-${PACKAGE_NAME}" \
        -v "${outdir}/archives":/packages/archives \
        centos:7.4.1708 \
        /bin/bash -c "\
            set -x
            yum install -y createrepo && \
            createrepo /packages/archives"
    sudo docker cp "rhel-7-createrepo-${PACKAGE_NAME}":/packages/archives "${outdir}"
    sudo chown -R $UID "${outdir}"
}

function build_rhel_8() {
    local packages=("$@")
    local outdir="${OUT_DIR}/rhel-8"

    mkdir -p "${outdir}"

    docker rm -f "rhel-8-${PACKAGE_NAME}" 2>/dev/null || true
    # Use the oldest OS minor version supported to ensure that updates required for outdated
    # packages are included.
    docker run \
        --name "rhel-8-${PACKAGE_NAME}" \
        centos:8.1.1911 \
        /bin/bash -c "\
            set -x
            yum install -y yum-utils epel-release && \
            mkdir -p /packages/archives && \
            yumdownloader --installroot=/tmp/empty-directory --releasever=/ --resolve --destdir=/packages/archives -y ${packages[*]}"
    sudo docker cp "rhel-8-${PACKAGE_NAME}":/packages/archives "${outdir}"
    sudo chown -R $UID "${outdir}"
}

function createrepo_rhel_8() {
    local outdir=
    outdir="$(realpath "${OUT_DIR}")/rhel-8"

    docker rm -f "rhel-8-createrepo-${PACKAGE_NAME}" 2>/dev/null || true
    # Use the oldest OS minor version supported to ensure that updates required for outdated
    # packages are included.
    docker run \
        --name "rhel-8-createrepo-${PACKAGE_NAME}" \
        -v "${outdir}/archives":/packages/archives \
        centos:8.1.1911 \
        /bin/bash -c "\
            set -x
            yum install -y createrepo && \
            createrepo /packages/archives"
    sudo docker cp "rhel-8-createrepo-${PACKAGE_NAME}":/packages/archives "${outdir}"
    sudo chown -R $UID "${outdir}"
}

pkgs_rhel7=()
pkgs_rhel8=()

while read -r line; do
    if [ -z "$line" ]; then
        continue
    fi
    # support for comments in manifest files
    if [ "$(echo $line | cut -c1-1)" = "#" ]; then
        continue
    fi
    kind=$(echo $line | awk '{ print $1 }')

    echo "LINE $line"

    case "$kind" in
        image)
            filename=$(echo $line | awk '{ print $2 }')
            image=$(echo $line | awk '{ print $3 }')
            docker pull $image
            mkdir -p $OUT_DIR/images
            docker save $image | gzip > $OUT_DIR/images/${filename}.tar.gz
            ;;

        asset)
            mkdir -p $OUT_DIR/assets
            filename=$(echo $line | awk '{ print $2 }')
            url=$(echo $line | awk '{ print $3 }')
            curl -L "$url" > "$OUT_DIR/assets/$filename"
            ;;

        apt)
            mkdir -p $OUT_DIR/ubuntu-20.04 $OUT_DIR/ubuntu-18.04 $OUT_DIR/ubuntu-16.04
            package=$(echo $line | awk '{ print $2 }')

            docker rm -f ubuntu-2004-${package} 2>/dev/null || true
            docker run \
                --name ubuntu-2004-${package} \
                ubuntu:20.04 \
                /bin/bash -c "\
                    mkdir -p /packages/archives && \
                    apt update -y \
                    && apt install -d --no-install-recommends -y $package \
                    -oDebug::NoLocking=1 -o=dir::cache=/packages/"
            docker cp ubuntu-2004-${package}:/packages/archives $OUT_DIR/ubuntu-20.04
            sudo chown -R $UID $OUT_DIR/ubuntu-20.04

            docker rm -f ubuntu-1804-${package} 2>/dev/null || true
            docker run \
                --name ubuntu-1804-${package} \
                ubuntu:18.04 \
                /bin/bash -c "\
                    mkdir -p /packages/archives && \
                    apt update -y \
                    && apt install -d --no-install-recommends -y $package \
                    -oDebug::NoLocking=1 -o=dir::cache=/packages/"
            docker cp ubuntu-1804-${package}:/packages/archives $OUT_DIR/ubuntu-18.04
            sudo chown -R $UID $OUT_DIR/ubuntu-18.04

            docker rm -f ubuntu-1604-${package} 2>/dev/null || true
            docker run \
                --name ubuntu-1604-${package} \
                ubuntu:16.04 \
                /bin/bash -c "\
                    mkdir -p /packages/archives && \
                    apt update -y \
                    && apt install -d --no-install-recommends -y $package \
                    -oDebug::NoLocking=1 -o=dir::cache=/packages/"
            docker cp ubuntu-1604-${package}:/packages/archives $OUT_DIR/ubuntu-16.04
            sudo chown -R $UID $OUT_DIR/ubuntu-16.04
            ;;

        yum)
            package=$(echo "${line}" | awk '{ print $2 }')
            pkgs_rhel7+=("${package}")
            pkgs_rhel8+=("${package}")
            ;;

        yum8)
            package=$(echo "${line}" | awk '{ print $2 }')
            pkgs_rhel8+=("${package}")
            ;;

        dockerout)
            dstdir=$(echo $line | awk '{ print $2 }')
            dockerfile=$(echo $line | awk '{ print $3 }')
            version=$(echo $line | awk '{ print $4 }')

            outdir="$OUT_DIR/$dstdir"
            name=$(< /dev/urandom tr -dc a-z | head -c8)

            mkdir -p $outdir

            docker build --build-arg VERSION=$version -t "$name" - < "$dockerfile"
            docker run --rm -v $outdir:/out $name
            sudo chown -R $UID $outdir
            ;;

        *)
            echo "Unknown kind $kind in line: $line"
            exit 1
            ;;
    esac
done < "${MANIFEST_PATH}"

if [ "${#pkgs_rhel7[@]}" -gt "0" ]; then
    build_rhel_7 "${pkgs_rhel7[@]}"
fi
if [ "$(ls -A "${OUT_DIR}/rhel-7")" ]; then
    createrepo_rhel_7
fi
if [ "${#pkgs_rhel8[@]}" -gt "0" ]; then
    build_rhel_8 "${pkgs_rhel8[@]}"
fi
if [ "$(ls -A "${OUT_DIR}/rhel-8")" ]; then
    createrepo_rhel_8
fi
