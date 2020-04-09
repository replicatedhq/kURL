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
    docker_pkg
}

# always build the common package
make dist/common.tar.gz

for package in $(list_all_packages)
do
    if ! aws s3api head-object --bucket=$S3_BUCKET --key=staging/$package &>/dev/null; then
        make dist/$package
    else
        echo "s3://$S3_BUCKET/staging/$package already exists"
    fi
done

aws s3 cp dist/ s3://$S3_BUCKET/staging --recursive
