#!/usr/bin/env bash

function require() {
    if [ -z "$2" ]; then
      echo "validation failed: $1 unset"
      exit 1
    fi
}

require WORKDIR "${WORKDIR}"
require DOCKERFILE "${DOCKERFILE}"

set -veuo pipefail

docker build -f ${DOCKERFILE} \
 --build-arg version=${CIRCLE_SHA1:0:7} \
 --build-arg KURL_UTIL_IMAGE \
 -t ${CIRCLE_PROJECT_REPONAME}:${CIRCLE_SHA1:0:7} \
 ${WORKDIR:-$HOME/repo}
