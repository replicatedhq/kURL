#!/bin/bash

MANIFEST_PATH=$1
OUT_DIR=$2

mkdir -p "$OUT_DIR"

while read -r line; do
    filename=$(echo $line | awk '{ print $1 }')
    image=$(echo $line | awk '{ print $2 }')
    docker pull $image
    docker save $image | gzip > $OUT_DIR/${filename}.tar.gz
done <  $MANIFEST_PATH
