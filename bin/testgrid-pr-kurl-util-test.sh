#!/bin/bash

# Tests for testgrid_pr_kurl_util_image() in testgrid-pr-kurl-util.sh.
#
# kurl.sh fills a rendered install.tmpl/join.tmpl/upgrade.tmpl/tasks.tmpl's
# KURL_UTIL_IMAGE placeholder by convention: replicated/kurl-util:<version>,
# the exact per-version tag deploy-staging.yaml always pushes for a real
# release. A testgrid-pr run must resolve to that same versioned tag whether
# or not it built a fresh branch-specific image (kURL#6188): the skip path
# retags+pushes the existing :alpha under the version tag instead of a fresh
# build, but the tag the installer templates resolve to is identical either
# way.

# shellcheck source=testgrid-pr-kurl-util.sh
. ./bin/testgrid-pr-kurl-util.sh

testResolvesVersionedTagWhenBuildSkipped() {
    local result
    result="$(testgrid_pr_kurl_util_image "v2026.10.07-0-rc-pr6188-abc1234")"

    assertEquals "replicated/kurl-util:v2026.10.07-0-rc-pr6188-abc1234" "${result}"
}

testResolvesVersionedTagWhenBuildRequested() {
    # The resolved tag is the same regardless of build-kurl-util-image --
    # only the workflow's mechanism for getting an image under that tag
    # differs (build fresh vs. retag :alpha), not the tag itself.
    local result
    result="$(testgrid_pr_kurl_util_image "v2026.10.07-0-rc-feature-branch-abc1234")"

    assertEquals "replicated/kurl-util:v2026.10.07-0-rc-feature-branch-abc1234" "${result}"
}

# shellcheck source=/dev/null
. shunit2
