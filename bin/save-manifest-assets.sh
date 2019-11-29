#!/bin/bash

set -e

MANIFEST_PATH=$1
OUT_DIR=$2

mkdir -p "$OUT_DIR"

while read -r line; do
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
            ;;
        *)
            echo "Unknown kind $kind in line: $line"
            exit 1
            ;;
    esac
done <  $MANIFEST_PATH
