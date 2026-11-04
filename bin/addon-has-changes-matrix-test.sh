#!/bin/bash

# Tests for addon_run_prefix() in addon-has-changes-matrix.sh.

# shellcheck source=addon-has-changes-matrix.sh
. ./bin/addon-has-changes-matrix.sh

testPrefixUsesPrHeadShaWhenSet() {
    local result
    result="$(PR_HEAD_SHA="abcdef1234567890" GITHUB_SHA="1111111deadbeef" GITHUB_REF="refs/pull/6176/merge" addon_run_prefix)"

    assertEquals "pr-6176-abcdef1" "${result}"
}

testPrefixFallsBackToGithubShaWhenPrHeadShaUnset() {
    local result
    result="$(unset PR_HEAD_SHA; GITHUB_SHA="1111111deadbeef" GITHUB_REF="refs/pull/6176/merge" addon_run_prefix)"

    assertEquals "pr-6176-1111111" "${result}"
}

# shellcheck source=/dev/null
. shunit2
