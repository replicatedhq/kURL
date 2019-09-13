#!/bin/bash

set -eo pipefail

function require() {
    if [ -z "$2" ]; then
        echo "validation failed: $1 unset"
        exit 1
    fi
}

require AWS_ACCESS_KEY_ID "${AWS_ACCESS_KEY_ID}"
require AWS_SECRET_ACCESS_KEY "${AWS_SECRET_ACCESS_KEY}"
require S3_BUCKET "${S3_BUCKET}"

DIST_ORIGIN=https://${S3_BUCKET}.s3.amazonaws.com

mkdir -p tmp/work

make build/install.sh build/join.sh build/upgrade.sh

cp build/install.sh tmp/work/
cp build/join.sh tmp/work/
cp build/upgrade.sh tmp/work/

# get latest versions
. scripts/Manifest

cd tmp/work

curl -L "${DIST_ORIGIN}/dist/common.tar.gz" | tar zxf -
curl -L "${DIST_ORIGIN}/dist/kubernetes-${KUBERNETES_VERSION}.tar.gz" | tar zxf -
curl -L "${DIST_ORIGIN}/dist/docker-${DOCKER_VERSION}.tar.gz"         | tar zxf -
curl -L "${DIST_ORIGIN}/dist/weave-${WEAVE_VERSION}.tar.gz"           | tar zxf -
curl -L "${DIST_ORIGIN}/dist/rook-${ROOK_VERSION}.tar.gz"             | tar zxf -
curl -L "${DIST_ORIGIN}/dist/contour-${CONTOUR_VERSION}.tar.gz"       | tar zxf -
curl -L "${DIST_ORIGIN}/dist/registry-${REGISTRY_VERSION}.tar.gz"     | tar zxf -

cd ..
tar czf latest.tar.gz -C work .

aws s3 cp latest.tar.gz s3://${S3_BUCKET}/bundle/latest.tar.gz
