#!/bin/bash

# Generate the list of all packages to be uploaded, then filter that based on CircleCI parallelism
# environment variables.

set -euo pipefail

function require() {
    if [ -z "$2" ]; then
        echo "validation failed: $1 unset"
        exit 1
    fi
}

require AWS_ACCESS_KEY_ID "${AWS_ACCESS_KEY_ID}"
require AWS_SECRET_ACCESS_KEY "${AWS_SECRET_ACCESS_KEY}"
require CIRCLE_NODE_TOTAL "${CIRCLE_NODE_TOTAL}"
require CIRCLE_NODE_INDEX "${CIRCLE_NODE_INDEX}"
require S3_BUCKET "${S3_BUCKET}"

function pkgs() {
    for dir in $(find $1 -mindepth 2 -maxdepth 2 -type d)
    do
        local name=$(echo $dir | awk -F "/" '{print $2 }')
        local version=$(echo $dir | awk -F "/" '{print $3 }')
        echo "${name}-${version}.tar.gz"
    done
}

function docker_pkg() {
    echo "docker-18.09.8.tar.gz"
    echo "docker-19.03.4.tar.gz"
}

function list_all_packages() {
    pkgs addons
    pkgs packages
    echo "common.tar.gz"
    docker_pkg
}

for package in $(list_all_packages | sort | awk "NR % $CIRCLE_NODE_TOTAL == $CIRCLE_NODE_INDEX")
do
    echo "Making $package"
    make dist/$package
done

aws s3 cp dist/ s3://$S3_BUCKET/dist --recursive
