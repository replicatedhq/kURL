#!/bin/bash

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <packages>"
    exit 1
fi

mkdir -p /packages/archives
#shellcheck disable=SC2086
yumdownloader --releasever=/ --destdir=/packages/archives -y $1
