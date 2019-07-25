#!/bin/bash

. ./install_scripts/templates/common/docker-version.sh

testParseDockerVersion()
{
    parseDockerVersion "1.13.1"
    assertEquals "Docker version major not equal" "1" "$DOCKER_VERSION_MAJOR"
    assertEquals "Docker version minor not equal" "13" "$DOCKER_VERSION_MINOR"
    assertEquals "Docker version patch not equal" "1" "$DOCKER_VERSION_PATCH"
    assertEquals "Docker version release not equal" "" "$DOCKER_VERSION_RELEASE"
}

testDockerVersionCE()
{
    parseDockerVersion "17.03.0-ce"
    assertEquals "Docker version major not equal" "17" "$DOCKER_VERSION_MAJOR"
    assertEquals "Docker version minor not equal" "03" "$DOCKER_VERSION_MINOR"
    assertEquals "Docker version patch not equal" "0" "$DOCKER_VERSION_PATCH"
    assertEquals "Docker version release not equal" "ce" "$DOCKER_VERSION_RELEASE"
}

testCompareDockerVersionsEq()
{
    compareDockerVersions "1.13.1" "1.13.1"
    assertEquals "Docker versions eq comparison failed 1.13.1 1.13.1" "0" "$COMPARE_DOCKER_VERSIONS_RESULT"

    compareDockerVersions "17.03.0-ce" "17.03.0-ce"
    assertEquals "Docker versions eq comparison failed 17.03.0-ce 17.03.0-ce" "0" "$COMPARE_DOCKER_VERSIONS_RESULT"
}

testCompareDockerVersionsLt()
{
    compareDockerVersions "1.12.1" "1.13.1"
    assertEquals "Docker versions lt comparison failed 1.12.1 1.13.1" "-1" "$COMPARE_DOCKER_VERSIONS_RESULT"

    compareDockerVersions "1.13.0" "1.13.1"
    assertEquals "Docker versions lt comparison failed 1.13.0 1.13.1" "-1" "$COMPARE_DOCKER_VERSIONS_RESULT"

    compareDockerVersions "1.13.1" "17.03.0-ce"
    assertEquals "Docker versions lt comparison failed 1.13.1 17.03.0-ce" "-1" "$COMPARE_DOCKER_VERSIONS_RESULT"

    compareDockerVersions "17.03.0-ce" "17.04.0-ce"
    assertEquals "Docker versions lt comparison failed 17.03.0-ce 17.04.0-ce" "-1" "$COMPARE_DOCKER_VERSIONS_RESULT"
}

testCompareDockerVersionsGt()
{
    compareDockerVersions "1.13.1" "1.12.1"
    assertEquals "Docker versions gt comparison failed 1.13.1 1.12.1" "1" "$COMPARE_DOCKER_VERSIONS_RESULT"

    compareDockerVersions "1.13.1" "1.13.0"
    assertEquals "Docker versions gt comparison failed 1.13.1 1.13.0" "1" "$COMPARE_DOCKER_VERSIONS_RESULT"

    compareDockerVersions "17.03.0-ce" "1.13.1"
    assertEquals "Docker versions gt comparison failed 17.03.0-ce 1.13.1" "1" "$COMPARE_DOCKER_VERSIONS_RESULT"

    compareDockerVersions "17.04.0-ce" "17.03.0-ce"
    assertEquals "Docker versions gt comparison failed 17.04.0-ce 17.03.0-ce" "1" "$COMPARE_DOCKER_VERSIONS_RESULT"
}

testCompareDockerVersionsIgnorePatch()
{
    compareDockerVersionsIgnorePatch "1.13.1" "1.13.1"
    assertEquals "Docker versions gt comparison failed 1.13.1 1.13.1" "0" "$COMPARE_DOCKER_VERSIONS_RESULT"

    compareDockerVersionsIgnorePatch "1.13.1" "1.13.0"
    assertEquals "Docker versions gt comparison failed 1.13.1 1.13.0" "0" "$COMPARE_DOCKER_VERSIONS_RESULT"

    compareDockerVersionsIgnorePatch "1.13.1" "1.13.2"
    assertEquals "Docker versions gt comparison failed 1.13.1 1.13.0" "0" "$COMPARE_DOCKER_VERSIONS_RESULT"

    compareDockerVersionsIgnorePatch "1.13.1" "1.12.1"
    assertEquals "Docker versions gt comparison failed 1.13.1 1.12.1" "1" "$COMPARE_DOCKER_VERSIONS_RESULT"
}

. shunit2
