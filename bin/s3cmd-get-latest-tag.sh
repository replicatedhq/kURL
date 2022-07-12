#!/bin/bash

set -e

function main() {
    get_latest_tag
}

function get_latest_tag() {
    docker run quay.io/skopeo/stable --override-os linux \
        list-tags "docker://kurlsh/s3cmd" \
        | jq -r '.Tags | .[]' \
        | grep -E "^2[0-9]{7}-" \
        | sort -r \
        | head -n 1
}

main "$@"
