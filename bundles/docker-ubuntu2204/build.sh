#!/bin/bash -x

set -e

DOCKER_VERSION="$1"
OUTPATH="$2"

semverParse() {
    major="${1%%.*}"
    minor="${1#$major.}"
    minor="${minor%%.*}"
    patch="${1#$major.$minor.}"
    patch="${patch%%[-.]*}"
}

SEMVER_COMPARE_RESULT=
semverCompare() {
    semverParse "$1"
    _a_major="${major:-0}"
    _a_minor="${minor:-0}"
    _a_patch="${patch:-0}"
    semverParse "$2"
    _b_major="${major:-0}"
    _b_minor="${minor:-0}"
    _b_patch="${patch:-0}"
    if [ "$_a_major" -lt "$_b_major" ]; then
        SEMVER_COMPARE_RESULT=-1
        return
    fi
    if [ "$_a_major" -gt "$_b_major" ]; then
        SEMVER_COMPARE_RESULT=1
        return
    fi
    if [ "$_a_minor" -lt "$_b_minor" ]; then
        SEMVER_COMPARE_RESULT=-1
        return
    fi
    if [ "$_a_minor" -gt "$_b_minor" ]; then
        SEMVER_COMPARE_RESULT=1
        return
    fi
    if [ "$_a_patch" -lt "$_b_patch" ]; then
        SEMVER_COMPARE_RESULT=-1
        return
    fi
    if [ "$_a_patch" -gt "$_b_patch" ]; then
        SEMVER_COMPARE_RESULT=1
        return
    fi
    SEMVER_COMPARE_RESULT=0
}

semverCompare "$DOCKER_VERSION" "20.10.17"
if [ "$SEMVER_COMPARE_RESULT" = "-1" ]; then
    # Docker 20.10.17 is the minimum supported version on Ubuntu 22.04
    exit 0
fi

docker build \
    --build-arg DOCKER_VERSION=${DOCKER_VERSION} \
    -t kurl/ubuntu-2204-docker:${DOCKER_VERSION} \
    -f bundles/docker-ubuntu2204/Dockerfile \
    bundles/docker-ubuntu2204
docker rm -f docker-ubuntu2204-${DOCKER_VERSION} 2>/dev/null || true
docker create --name docker-ubuntu2204-${DOCKER_VERSION} kurl/ubuntu-2204-docker:${DOCKER_VERSION}
mkdir -p build/packages/docker/${DOCKER_VERSION}/ubuntu-22.04
docker cp docker-ubuntu2204-${DOCKER_VERSION}:/packages/archives/. "$OUTPATH"
docker rm docker-ubuntu2204-${DOCKER_VERSION}
