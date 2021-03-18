#!/bin/bash

set -e

MANIFEST_PATH=$1
OUT_DIR=$2

mkdir -p "$OUT_DIR"

function build_rhel_8() {
    local package="$1"
    docker rm -f rhel-8-${package} 2>/dev/null || true
    # Use the oldest OS minor version supported to ensure that updates required for outdated
    # packages are included.
    docker run \
        --name rhel-8-${package} \
        centos:8.1.1911 \
        /bin/bash -c "\
        yum install -y yum-utils epel-release && \
        mkdir -p /packages/archives && \
        yumdownloader --resolve --destdir=/packages/archives -y $package"
    docker cp rhel-8-${package}:/packages/archives $OUT_DIR/rhel-8
    sudo chown -R $UID $OUT_DIR/rhel-8
}

while read -r line; do
    if [ -z "$line" ]; then
        continue
    fi
    # support for comments in manifest files
    if [ "$(echo $line | cut -c1-1)" = "#" ]; then
        continue
    fi
    kind=$(echo $line | awk '{ print $1 }')

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
            mkdir -p $OUT_DIR/rhel-7 $OUT_DIR/rhel-8
            package=$(echo $line | awk '{ print $2 }')

            docker rm -f rhel-7-${package} 2>/dev/null || true
            # Use the oldest OS minor version supported to ensure that updates required for outdated
            # packages are included
            docker run \
                --name rhel-7-${package} \
                centos:7.4.1708 \
                /bin/bash -c "\
                    yum install -y epel-release && \
                    mkdir -p /packages/archives && \
                    yumdownloader --resolve --destdir=/packages/archives -y $package"
            docker cp rhel-7-${package}:/packages/archives $OUT_DIR/rhel-7
            sudo chown -R $UID $OUT_DIR/rhel-7

            build_rhel_8 "$package"
            ;;

        yum8)
            mkdir -p $OUT_DIR/rhel-8
            package=$(echo $line | awk '{ print $2 }')

            build_rhel_8 "$package"
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
done <  $MANIFEST_PATH
