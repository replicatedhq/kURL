#!/bin/bash

# Tests for stale_testgrid_refs() in cancel-stale-testgrid-runs.sh.

# shellcheck source=cancel-stale-testgrid-runs.sh
. ./bin/cancel-stale-testgrid-runs.sh

HEAD_SHA="abc1234def5678"

testCancelsAddonRunFromOlderCommit() {
    local result
    result="$(echo "pr-6232-1413a13-rook-1.20.10-k8s-docker-2026-11-16T01:17:25Z 10 2" \
        | stale_testgrid_refs 6232 "${HEAD_SHA}")"

    assertEquals "pr-6232-1413a13-rook-1.20.10-k8s-docker-2026-11-16T01:17:25Z" "${result}"
}

testCancelsCoreRunFromOlderCommit() {
    local result
    result="$(echo "PR-v2026.11.13-0-rc-pr6232-1413a13-2026-11-16T01:17:25Z 0 3" \
        | stale_testgrid_refs 6232 "${HEAD_SHA}")"

    assertEquals "PR-v2026.11.13-0-rc-pr6232-1413a13-2026-11-16T01:17:25Z" "${result}"
}

testKeepsRunsForHeadCommit() {
    local result
    result="$(printf '%s\n' \
        "pr-6232-abc1234-rook-1.20.10-k8s-docker-2026-11-16T01:17:25Z 10 2" \
        "PR-v2026.11.13-0-rc-pr6232-abc1234-2026-11-16T01:17:25Z 5 0" \
        | stale_testgrid_refs 6232 "${HEAD_SHA}")"

    assertEquals "" "${result}"
}

testIgnoresOtherPullRequests() {
    # searchRef is a substring match, so rc-pr623- also returns PR 6232's
    # core runs (and rc-pr6232- PR 62320's).
    local result
    result="$(printf '%s\n' \
        "pr-6232-1413a13-rook-1.20.10-k8s-docker-2026-11-16T01:17:25Z 10 2" \
        "PR-v2026.11.13-0-rc-pr6232-1413a13-2026-11-16T01:17:25Z 5 0" \
        | stale_testgrid_refs 623 "${HEAD_SHA}")"
    assertEquals "" "${result}"

    result="$(printf '%s\n' \
        "pr-62320-1413a13-rook-1.20.10-k8s-docker-2026-11-16T01:17:25Z 10 2" \
        "PR-v2026.11.13-0-rc-pr62320-1413a13-2026-11-16T01:17:25Z 5 0" \
        | stale_testgrid_refs 6232 "${HEAD_SHA}")"
    assertEquals "" "${result}"
}

testOnlyCancelsStaleRunsFromMixedInput() {
    local result
    result="$(printf '%s\n' \
        "pr-6232-abc1234-rook-1.20.10-k8s-docker-2026-11-16T01:17:25Z 10 2" \
        "pr-62320-1413a13-rook-1.20.10-k8s-docker-2026-11-16T01:17:25Z 10 2" \
        "pr-6232-2c25459-rook-1.20.9-k8s-docker-2026-11-02T01:16:05Z 0 0" \
        "pr-6232-1413a13-rook-1.20.10-k8s-docker-2026-11-16T01:17:25Z 3 0" \
        | stale_testgrid_refs 6232 "${HEAD_SHA}")"

    assertEquals "pr-6232-1413a13-rook-1.20.10-k8s-docker-2026-11-16T01:17:25Z" "${result}"
}

testRejectsInvalidHeadSha() {
    # Otherwise no ref's sha would match the head and the head commit's own
    # runs would be cancelled.
    local head result rc
    for head in "" "null" "abc" "ABC1234DEF"; do
        rc=0
        result="$(echo "pr-6232-abc1234-rook-1.20.10-k8s-docker-2026-11-16T01:17:25Z 10 2" \
            | stale_testgrid_refs 6232 "${head}" 2>/dev/null)" || rc=$?
        assertEquals "head '${head}' printed refs" "" "${result}"
        assertNotEquals "head '${head}' did not fail" 0 "${rc}"
    done
}

testSkipsFinishedRuns() {
    local result
    result="$(echo "pr-6232-1413a13-rook-1.20.10-k8s-docker-2026-11-16T01:17:25Z 0 0" \
        | stale_testgrid_refs 6232 "${HEAD_SHA}")"

    assertEquals "" "${result}"
}

testIgnoresDispatchedBranchRuns() {
    local result
    result="$(echo "PR-v2026.11.13-0-rc-my-branch-1413a13-2026-11-16T01:17:25Z 5 0" \
        | stale_testgrid_refs 6232 "${HEAD_SHA}")"

    assertEquals "" "${result}"
}

testListStopsWhenApiUnreachable() {
    # Must return rather than page forever (it runs where set -e is off).
    curl() { return 22; }
    local rc=0
    ( list_testgrid_runs "pr-6232-" >/dev/null 2>&1 ) || rc=$?
    unset -f curl

    assertNotEquals 0 "${rc}"
}

# shellcheck source=/dev/null
. shunit2
