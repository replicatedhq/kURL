#!/bin/bash

# Tests for retry() and retag_and_push_kurl_util_image() in
# retag-and-push-kurl-util-image.sh -- the retag+push path testgrid-pr.yaml
# runs on every label-triggered PR testgrid run (build-kurl-util-image=false)
# to publish the per-version RC tag the generated installer/kurlnet manifests
# are pinned to (replicatedhq/kURL#6171 bug 2).
#
# This path had zero test coverage before: a transient DockerHub failure must
# be retried, not left to fail the whole get-tag -> kurl-util-image chain on
# the first hiccup, and the retries must not run forever.

# shellcheck source=retag-and-push-kurl-util-image.sh
. ./bin/retag-and-push-kurl-util-image.sh

# sleep is stubbed out everywhere in this suite so retry's exponential
# backoff doesn't actually slow the test run down.
sleep() { :; }

oneTimeSetUp() {
    DOCKER_CALLS_FILE="$(mktemp)"
}

oneTimeTearDown() {
    rm -f "${DOCKER_CALLS_FILE}"
}

setUp() {
    : > "${DOCKER_CALLS_FILE}"
    DOCKER_PULL_FAILURES_REMAINING=0
    DOCKER_PULL_EXIT_CODE=1
    DOCKER_TAG_FAILURES_REMAINING=0
    DOCKER_TAG_EXIT_CODE=1
    DOCKER_PUSH_FAILURES_REMAINING=0
    DOCKER_PUSH_EXIT_CODE=1
}

# docker stub: records every invocation, and lets a test script a fixed
# number of "docker pull"/"docker tag"/"docker push" failures before
# succeeding.
docker() {
    echo "$*" >> "${DOCKER_CALLS_FILE}"

    if [ "$1" = "pull" ] && [ "${DOCKER_PULL_FAILURES_REMAINING}" -gt 0 ]; then
        DOCKER_PULL_FAILURES_REMAINING=$((DOCKER_PULL_FAILURES_REMAINING - 1))
        return "${DOCKER_PULL_EXIT_CODE}"
    fi

    if [ "$1" = "tag" ] && [ "${DOCKER_TAG_FAILURES_REMAINING}" -gt 0 ]; then
        DOCKER_TAG_FAILURES_REMAINING=$((DOCKER_TAG_FAILURES_REMAINING - 1))
        return "${DOCKER_TAG_EXIT_CODE}"
    fi

    if [ "$1" = "push" ] && [ "${DOCKER_PUSH_FAILURES_REMAINING}" -gt 0 ]; then
        DOCKER_PUSH_FAILURES_REMAINING=$((DOCKER_PUSH_FAILURES_REMAINING - 1))
        return "${DOCKER_PUSH_EXIT_CODE}"
    fi

    return 0
}

testRetrySucceedsOnFirstAttempt() {
    local calls=0
    pass() { calls=$((calls + 1)); return 0; }

    retry 5 pass
    assertEquals "0" "$?"
    assertEquals "1" "${calls}"
}

testRetrySucceedsAfterTransientFailures() {
    local attempts=0
    flaky() {
        attempts=$((attempts + 1))
        [ "${attempts}" -ge 3 ]
    }

    retry 5 flaky
    assertEquals "0" "$?"
    assertEquals "3" "${attempts}"
}

testRetryExhaustsAllAttemptsAndReturnsStubExitCode() {
    local attempts=0
    alwaysFails() {
        attempts=$((attempts + 1))
        return 7
    }

    retry 5 alwaysFails
    assertEquals "7" "$?"
    assertEquals "5" "${attempts}"
}

testRetagAndPushPullsTagsAndPushesCorrectPair() {
    retag_and_push_kurl_util_image "replicated/kurl-util:alpha" "replicated/kurl-util:v1.2.3-rc"
    assertEquals "0" "$?"

    local calls
    calls="$(cat "${DOCKER_CALLS_FILE}")"
    assertEquals "$(printf 'pull replicated/kurl-util:alpha\ntag replicated/kurl-util:alpha replicated/kurl-util:v1.2.3-rc\npush replicated/kurl-util:v1.2.3-rc')" "${calls}"
}

testRetagAndPushRetriesPullOnTransientFailure() {
    DOCKER_PULL_FAILURES_REMAINING=2

    retag_and_push_kurl_util_image "replicated/kurl-util:alpha" "replicated/kurl-util:v1.2.3-rc"
    assertEquals "0" "$?"

    local pull_calls
    pull_calls="$(grep -c "^pull " "${DOCKER_CALLS_FILE}")"
    assertEquals "3" "${pull_calls}"
}

testRetagAndPushRetriesPushOnTransientFailure() {
    DOCKER_PUSH_FAILURES_REMAINING=2

    retag_and_push_kurl_util_image "replicated/kurl-util:alpha" "replicated/kurl-util:v1.2.3-rc"
    assertEquals "0" "$?"

    local push_calls
    push_calls="$(grep -c "^push " "${DOCKER_CALLS_FILE}")"
    assertEquals "3" "${push_calls}"
}

testRetagAndPushExhaustsPushRetriesAndReturnsStubExitCode() {
    DOCKER_PUSH_FAILURES_REMAINING=5
    DOCKER_PUSH_EXIT_CODE=17

    retag_and_push_kurl_util_image "replicated/kurl-util:alpha" "replicated/kurl-util:v1.2.3-rc"
    assertEquals "17" "$?"

    local push_calls
    push_calls="$(grep -c "^push " "${DOCKER_CALLS_FILE}")"
    assertEquals "5" "${push_calls}"
}

testRetagAndPushShortCircuitsOnTagFailureAndDoesNotPush() {
    DOCKER_TAG_FAILURES_REMAINING=1
    DOCKER_TAG_EXIT_CODE=9

    retag_and_push_kurl_util_image "replicated/kurl-util:alpha" "replicated/kurl-util:v1.2.3-rc"
    assertEquals "9" "$?"

    local push_calls
    push_calls="$(grep -c "^push " "${DOCKER_CALLS_FILE}")"
    assertEquals "0" "${push_calls}"
}

testRetagAndPushRequiresSourceAndDestImages() {
    local output
    output="$(retag_and_push_kurl_util_image "replicated/kurl-util:alpha" "" 2>&1 >/dev/null)"
    assertEquals "1" "$?"
    assertEquals "retag_and_push_kurl_util_image: source_image and dest_image are required" "${output}"
}

testRetagScriptSourcesSharedRetryHelperInsteadOfDefiningItsOwnCopy() {
    # PR #6173 review (doomer-ai): this script's retry() was a third
    # hand-maintained copy of the exponential-backoff helper (bin/upload-
    # dist-staging.sh, and two inlined in testgrid-pr.yaml, already had
    # their own). Guard that it sources the shared bin/retry.sh instead of
    # redefining the function here, so the two can't drift apart.
    assertTrue "bin/retag-and-push-kurl-util-image.sh must source bin/retry.sh" \
        "grep -q '^\. \./bin/retry\.sh' ./bin/retag-and-push-kurl-util-image.sh"
    assertFalse "bin/retag-and-push-kurl-util-image.sh must not define its own retry()" \
        "grep -q '^function retry()' ./bin/retag-and-push-kurl-util-image.sh"
}

# shellcheck source=/dev/null
. shunit2
