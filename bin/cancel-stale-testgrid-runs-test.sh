#!/bin/bash

# Tests for cancel-stale-testgrid-runs.sh.

# shellcheck source=cancel-stale-testgrid-runs.sh
. ./bin/cancel-stale-testgrid-runs.sh
# The script's errexit would make shunit2 abort on the first failed assertion.
set +e +o pipefail

# Nothing must reach the real API.
# shellcheck disable=SC2034
TESTGRID_API="http://127.0.0.1:9"

HEAD_SHA="abc1234def5678"

testCancelsAddonRunFromOlderCommit() {
    local result
    result="$(echo "10 2 pr-6232-1413a13-rook-1.20.10-k8s-docker-2026-11-16T01:17:25Z" \
        | stale_testgrid_refs 6232 "${HEAD_SHA}")"

    assertEquals "pr-6232-1413a13-rook-1.20.10-k8s-docker-2026-11-16T01:17:25Z" "${result}"
}

testCancelsCoreRunFromOlderCommit() {
    local result
    result="$(echo "0 3 PR-v2026.11.13-0-rc-pr6232-1413a13-2026-11-16T01:17:25Z" \
        | stale_testgrid_refs 6232 "${HEAD_SHA}")"

    assertEquals "PR-v2026.11.13-0-rc-pr6232-1413a13-2026-11-16T01:17:25Z" "${result}"
}

testKeepsRunsForHeadCommit() {
    local result
    result="$(printf '%s\n' \
        "10 2 pr-6232-abc1234-rook-1.20.10-k8s-docker-2026-11-16T01:17:25Z" \
        "5 0 PR-v2026.11.13-0-rc-pr6232-abc1234-2026-11-16T01:17:25Z" \
        | stale_testgrid_refs 6232 "${HEAD_SHA}")"

    assertEquals "" "${result}"
}

testIgnoresOtherPullRequests() {
    local result
    result="$(printf '%s\n' \
        "10 2 pr-62320-1413a13-rook-1.20.10-k8s-docker-2026-11-16T01:17:25Z" \
        "5 0 PR-v2026.11.13-0-rc-pr62320-1413a13-2026-11-16T01:17:25Z" \
        | stale_testgrid_refs 6232 "${HEAD_SHA}")"

    assertEquals "" "${result}"
}

testIgnoresRefsMentioningThePullRequestMidway() {
    # searchRef is a substring match, so pr-6072- also returns hand-named
    # reruns and dispatched branches that mention the PR.
    local result
    result="$(printf '%s\n' \
        "10 2 rerun-pr-6072-894be04-containerd-1.7.29-k8s-ctrd-2026-10-07T22:07:33Z" \
        "5 0 PR-v2026.11.13-0-rc-fix-pr-6072-followup-894be04a1-2026-11-16T01:17:25Z" \
        | stale_testgrid_refs 6072 "${HEAD_SHA}")"

    assertEquals "" "${result}"
}

testOnlyCancelsStaleRunsFromMixedInput() {
    local result
    result="$(printf '%s\n' \
        "10 2 pr-6232-abc1234-rook-1.20.10-k8s-docker-2026-11-16T01:17:25Z" \
        "10 2 pr-62320-1413a13-rook-1.20.10-k8s-docker-2026-11-16T01:17:25Z" \
        "0 0 pr-6232-2c25459-rook-1.20.9-k8s-docker-2026-11-02T01:16:05Z" \
        "3 0 pr-6232-1413a13-rook-1.20.10-k8s-docker-2026-11-16T01:17:25Z" \
        | stale_testgrid_refs 6232 "${HEAD_SHA}")"

    assertEquals "pr-6232-1413a13-rook-1.20.10-k8s-docker-2026-11-16T01:17:25Z" "${result}"
}

testSkipsFinishedRuns() {
    local result
    result="$(echo "0 0 pr-6232-1413a13-rook-1.20.10-k8s-docker-2026-11-16T01:17:25Z" \
        | stale_testgrid_refs 6232 "${HEAD_SHA}")"

    assertEquals "" "${result}"
}

testIgnoresDispatchedBranchRuns() {
    local result
    result="$(echo "5 0 PR-v2026.11.13-0-rc-my-branch-1413a13-2026-11-16T01:17:25Z" \
        | stale_testgrid_refs 6232 "${HEAD_SHA}")"

    assertEquals "" "${result}"
}

testKeepsRefWithSpacesWhole() {
    local result
    result="$(echo "1 0 pr-6232-1413a13-rook-1.20.10-k8s docker-2026-11-16T01:17:25Z" \
        | stale_testgrid_refs 6232 "${HEAD_SHA}")"

    assertEquals "pr-6232-1413a13-rook-1.20.10-k8s docker-2026-11-16T01:17:25Z" "${result}"
}

testRejectsNonNumericCounts() {
    # e.g. jq printing null after an API field rename.
    local result rc=0
    result="$(echo "null null pr-6232-1413a13-rook-1.20.10-k8s-docker-2026-11-16T01:17:25Z" \
        | stale_testgrid_refs 6232 "${HEAD_SHA}" 2>/dev/null)" || rc=$?

    assertEquals "" "${result}"
    assertEquals 1 "${rc}"
}

testRejectsInvalidHeadSha() {
    # Otherwise no ref's sha would match the head and the head commit's own
    # runs would be cancelled.
    local head result rc
    for head in "" "null" "abc" "ABC1234DEF"; do
        rc=0
        result="$(echo "10 2 pr-6232-abc1234-rook-1.20.10-k8s-docker-2026-11-16T01:17:25Z" \
            | stale_testgrid_refs 6232 "${head}" 2>/dev/null)" || rc=$?
        assertEquals "head '${head}' printed refs" "" "${result}"
        assertEquals "head '${head}' did not fail" 1 "${rc}"
    done
}

testListFailsWhenApiUnreachable() {
    local rc=0
    ( curl() { return 22; }; list_testgrid_runs "pr-6232-" >/dev/null 2>&1 ) || rc=$?

    assertEquals 1 "${rc}"
}

testListPagesAndPrintsCountsFirst() {
    if ! command -v jq >/dev/null; then
        startSkipping
    fi
    local result
    result="$(
        curl() {
            case "$*" in
                *currentPage=0*) echo '{"total":2,"runs":[{"id":"pr-1-aaaaaaa-x","pending_runs":1,"running_runs":0}]}' ;;
                *currentPage=1*) echo '{"total":2,"runs":[{"id":"pr-1-bbbbbbb-x","pending_runs":0,"running_runs":2}]}' ;;
                *) return 22 ;;
            esac
        }
        list_testgrid_runs "pr-1-"
    )"

    assertEquals "$(printf '%s\n' "1 0 pr-1-aaaaaaa-x" "0 2 pr-1-bbbbbbb-x")" "${result}"
    endSkipping
}

testListFailsOnNonJsonResponse() {
    if ! command -v jq >/dev/null; then
        startSkipping
    fi
    local rc=0
    ( curl() { echo '<html>oops</html>'; }; list_testgrid_runs "pr-1-" >/dev/null 2>&1 ) || rc=$?

    assertEquals 1 "${rc}"
    endSkipping
}

testCancelFailsWhenCurlFails() {
    local rc=0
    ( curl() { return 22; }; cancel_testgrid_ref "pr-6232-1413a13-x" >/dev/null 2>&1 ) || rc=$?

    assertNotEquals 0 "${rc}"
}

# stub_main_deps replaces the network helpers for main: list_testgrid_runs
# prints $1 for the add-on search and $2 for the core search, and
# cancel_testgrid_ref records each ref in ${CANCELLED_FILE}, failing with $3.
stub_main_deps() {
    LIST_ADDON="$1"
    LIST_CORE="$2"
    CANCEL_RC="${3:-0}"
    list_testgrid_runs() {
        case "$1" in
            pr-*) [ -z "${LIST_ADDON}" ] || echo "${LIST_ADDON}" ;;
            rc-pr*) [ -z "${LIST_CORE}" ] || echo "${LIST_CORE}" ;;
        esac
    }
    cancel_testgrid_ref() {
        echo "$1" >> "${CANCELLED_FILE}"
        return "${CANCEL_RC}"
    }
}

setUp() {
    CANCELLED_FILE="$(mktemp)"
}

tearDown() {
    rm -f "${CANCELLED_FILE}"
}

testMainCancelsStaleAddonAndCoreRuns() {
    local rc=0
    ( stub_main_deps \
        "$(printf '%s\n' "3 0 pr-6232-1413a13-a" "3 0 pr-6232-abc1234-b")" \
        "1 0 PR-v2026.11.13-0-rc-pr6232-1413a13-2026-11-16T01:17:25Z"
      PR_NUMBER=6232 PR_HEAD_SHA="${HEAD_SHA}" main >/dev/null ) || rc=$?

    assertEquals 0 "${rc}"
    assertEquals "$(printf '%s\n' "pr-6232-1413a13-a" "PR-v2026.11.13-0-rc-pr6232-1413a13-2026-11-16T01:17:25Z")" \
        "$(cat "${CANCELLED_FILE}")"
}

testMainWarnsAndFailsWhenCancelFails() {
    local output rc=0
    output="$( stub_main_deps "3 0 pr-6232-1413a13-a" "" 1
      PR_NUMBER=6232 PR_HEAD_SHA="${HEAD_SHA}" main )" || rc=$?

    assertEquals 1 "${rc}"
    assertContains "${output}" "::warning ::failed to cancel Testgrid run pr-6232-1413a13-a"
}

testMainCancelsNothingWhenListingFails() {
    local rc=0
    ( stub_main_deps "3 0 pr-6232-1413a13-a" ""
      list_testgrid_runs() { return 1; }
      PR_NUMBER=6232 PR_HEAD_SHA="${HEAD_SHA}" main >/dev/null 2>&1 ) || rc=$?

    assertNotEquals 0 "${rc}"
    assertEquals "" "$(cat "${CANCELLED_FILE}")"
}

# shellcheck source=/dev/null
. shunit2
