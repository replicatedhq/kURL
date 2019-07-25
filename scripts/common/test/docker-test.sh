#!/bin/bash

. ./install_scripts/templates/common/docker.sh

testDockerReplaceRegistryAddress()
{
    REPO_TAG=
    dockerReplaceRegistryAddress "gcr.io/heptio-images/contour:v0.8.0" "localhost:31500"
    assertEquals "fully qualified image name" "localhost:31500/heptio-images/contour:v0.8.0" "$REPO_TAG"

    REPO_TAG=
    dockerReplaceRegistryAddress "k8s.gcr.io/kube-proxy:v1.13.0" "localhost:31500"
    assertEquals "no org" "localhost:31500/kube-proxy:v1.13.0" "$REPO_TAG"

    REPO_TAG=
    dockerReplaceRegistryAddress "weaveworks/weave-kube:2.5.0" "localhost:31500"
    assertEquals "official registry" "localhost:31500/weaveworks/weave-kube:2.5.0" "$REPO_TAG"

    REPO_TAG=
    dockerReplaceRegistryAddress "registry:2" "localhost:31500"
    assertEquals "official registry" "localhost:31500/library/registry:2" "$REPO_TAG"

    REPO_TAG=
    dockerReplaceRegistryAddress "replicated/studio" "localhost:31500"
    assertEquals "latest tag" "localhost:31500/replicated/studio" "$REPO_TAG"
}

. shunit2
