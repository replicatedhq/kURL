#!/bin/bash

set -e

. ./scripts/common/docker.sh
. ./scripts/common/kubernetes.sh

function test_kubernetes_node_has_image() {
    function kubernetes_node_images() {
        echo "docker.io/org/image-1:1.0
org/image-2:1.0
image-3:1.0
library/image-4:1.0
quay.io/org/image-5:1.0
quay.io/org/image-6"
    }
    export kubernetes_node_images

    assertEquals "docker.io/org/image-1:1.0 org/image-1:1.0" "0" "$(kubernetes_node_has_image "node-1" "org/image-1:1.0"; echo $?)"
    assertEquals "docker.io/org/image-1:1.0 docker.io/org/image-1:1.0" "0" "$(kubernetes_node_has_image "node-1" "docker.io/org/image-1:1.0"; echo $?)"

    assertEquals "org/image-2:1.0 org/image-2:1.0" "0" "$(kubernetes_node_has_image "node-1" "org/image-2:1.0"; echo $?)"
    assertEquals "org/image-2:1.0 docker.io/org/image-2:1.0" "0" "$(kubernetes_node_has_image "node-1" "docker.io/org/image-2:1.0"; echo $?)"

    assertEquals "image-3:1.0 image-3:1.0" "0" "$(kubernetes_node_has_image "node-1" "image-3:1.0"; echo $?)"
    assertEquals "image-3:1.0 library/image-3:1.0" "0" "$(kubernetes_node_has_image "node-1" "library/image-3:1.0"; echo $?)"
    assertEquals "image-3:1.0 docker.io/library/image-3:1.0" "0" "$(kubernetes_node_has_image "node-1" "docker.io/library/image-3:1.0"; echo $?)"

    assertEquals "library/image-4:1.0 image-4:1.0" "0" "$(kubernetes_node_has_image "node-1" "image-4:1.0"; echo $?)"
    assertEquals "library/image-4:1.0 library/image-4:1.0" "0" "$(kubernetes_node_has_image "node-1" "library/image-4:1.0"; echo $?)"
    assertEquals "library/image-4:1.0 docker.io/library/image-4:1.0" "0" "$(kubernetes_node_has_image "node-1" "docker.io/library/image-4:1.0"; echo $?)"

    assertEquals "quay.io/org/image-5:1.0 quay.io/org/image-5:1.0" "0" "$(kubernetes_node_has_image "node-1" "quay.io/org/image-5:1.0"; echo $?)"

    assertEquals "quay.io/org/image-6 quay.io/org/image-6" "0" "$(kubernetes_node_has_image "node-1" "quay.io/org/image-6"; echo $?)"
    assertEquals "quay.io/org/image-6 quay.io/org/image-6:latest" "0" "$(kubernetes_node_has_image "node-1" "quay.io/org/image-6:latest"; echo $?)"

    assertEquals "org/image-n:1.0" "1" "$(kubernetes_node_has_image "node-1" "org/image-n:1.0"; echo $?)"
    assertEquals "image-n:1.0" "1" "$(kubernetes_node_has_image "node-1" "image-n:1.0"; echo $?)"
    assertEquals "docker.io/org/image-n:1.0" "1" "$(kubernetes_node_has_image "node-1" "docker.io/org/image-n:1.0"; echo $?)"
    assertEquals "quay.io/org/image-n:1.0" "1" "$(kubernetes_node_has_image "node-1" "quay.io/org/image-n:1.0"; echo $?)"
    assertEquals "quay.io/org/image-n" "1" "$(kubernetes_node_has_image "node-1" "quay.io/org/image-n"; echo $?)"
    assertEquals "quay.io/org/image-5:2.0" "1" "$(kubernetes_node_has_image "node-1" "quay.io/org/image-5:2.0"; echo $?)"
}

. shunit2
