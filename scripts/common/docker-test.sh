#!/bin/bash

set -e

. ./scripts/common/docker.sh

function test_canonical_image_name() {
    assertEquals "docker.io/library/image:1.0" "$(canonical_image_name "image:1.0")"
    assertEquals "docker.io/library/image:1.0" "$(canonical_image_name "library/image:1.0")"
    assertEquals "docker.io/library/image:1.0" "$(canonical_image_name "docker.io/library/image:1.0")"
    assertEquals "docker.io/org/image:1.0" "$(canonical_image_name "org/image:1.0")"
    assertEquals "docker.io/org/image:1.0" "$(canonical_image_name "docker.io/org/image:1.0")"
    assertEquals "quay.io/org/image:1.0" "$(canonical_image_name "quay.io/org/image:1.0")"
    assertEquals "docker.io/library/image:latest" "$(canonical_image_name "image")"
    assertEquals "docker.io/library/image:latest" "$(canonical_image_name "library/image")"
    assertEquals "docker.io/library/image:latest" "$(canonical_image_name "docker.io/library/image")"
    assertEquals "docker.io/library/image:latest" "$(canonical_image_name "docker.io/library/image:latest")"
    assertEquals "docker.io/org/image:latest" "$(canonical_image_name "org/image:latest")"
    assertEquals "quay.io/org/image:latest" "$(canonical_image_name "quay.io/org/image:latest")"
}

. shunit2
