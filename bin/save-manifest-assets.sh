#!/bin/bash

set -e

MANIFEST_PATH=$1
OUT_DIR=$2

mkdir -p "$OUT_DIR"

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
            mkdir -p $OUT_DIR/ubuntu-18.04 $OUT_DIR/ubuntu-16.04
            package=$(echo $line | awk '{ print $2 }')

            docker run --rm \
                -v $OUT_DIR/ubuntu-18.04:/packages \
                ubuntu:18.04 \
                /bin/bash -c "\
                    mkdir -p /packages/archives && \
                    apt update -y \
                    && apt install -d -y $package \
                    -oDebug::NoLocking=1 -o=dir::cache=/packages/"
            sudo chown -R $UID $OUT_DIR/ubuntu-18.04

            docker run --rm \
                -v $OUT_DIR/ubuntu-16.04:/packages \
                ubuntu:16.04 \
                /bin/bash -c "\
                    mkdir -p /packages/archives && \
                    apt update -y \
                    && apt install -d -y $package \
                    -oDebug::NoLocking=1 -o=dir::cache=/packages/"
            sudo chown -R $UID $OUT_DIR/ubuntu-16.04
            ;;
        yum)
            mkdir -p $OUT_DIR/rhel-7
            package=$(echo $line | awk '{ print $2 }')

            docker run --rm \
                -v $OUT_DIR/rhel-7:/packages \
                centos:7 \
                /bin/bash -c "\
                    mkdir -p /packages/archives && \
                    yumdownloader --resolve --destdir=/packages/archives -y $package"
            sudo chown -R $UID $OUT_DIR/rhel-7
            ;;
        *)
            echo "Unknown kind $kind in line: $line"
            exit 1
            ;;
    esac
done <  $MANIFEST_PATH
