#!/bin/bash

# Cancels the Testgrid runs a PR queued for its earlier commits, so only the
# latest commit's runs use Testgrid capacity.
#
# A push to a PR cancels the older test-addon-pr.yaml workflow run
# (concurrency cancel-in-progress) but not the Testgrid runs it already
# queued, and testgrid-pr.yaml is label-triggered, so a push never touches its
# runs at all. This finds the PR's refs whose commit sha is not the PR's
# current head and cancels them via the Testgrid API, which drops pending
# instances and marks running ones cancelled (the runner hosts then delete
# their VMs).
#
# A PR's refs carry the head commit's short sha:
#   add-on runs (bin/addon-has-changes-matrix.sh):  pr-<N>-<sha7>-<addon>-...
#   core RC runs (testgrid-pr.yaml):                PR-<tag>-rc-pr<N>-<sha7>-<ts>

set -eo pipefail

TESTGRID_API="${TESTGRID_API:-https://api.testgrid.kurl.sh}"
CURL_OPTS=(-fsS --retry 3 --connect-timeout 10 --max-time 30)

function require() {
   if [ -z "$2" ]; then
       echo "validation failed: $1 unset"
       exit 1
   fi
}

# stale_testgrid_refs reads "<pending_runs> <running_runs> <ref>" lines on
# stdin and prints the refs that belong to PR $1, were queued for a commit
# other than $2 (the head sha, 7+ chars), and still have pending or running
# instances.
function stale_testgrid_refs() {
    local pr="$1"
    local head_sha="${2:0:7}"

    # A head that can never match a ref's sha would make every run stale,
    # including the head commit's own.
    if ! [[ "$2" =~ ^[0-9a-f]{7,40}$ ]]; then
        echo "invalid head sha: '$2'" >&2
        return 1
    fi

    local addon_re="^pr-${pr}-([0-9a-f]{7})-"
    local core_re="^PR-.*-rc-pr${pr}-([0-9a-f]{7})-"

    local pending running ref sha
    while read -r pending running ref; do
        [ -n "${ref}" ] || continue
        if ! [[ "${pending}" =~ ^[0-9]+$ && "${running}" =~ ^[0-9]+$ ]]; then
            echo "unexpected run counts for ${ref}: '${pending}' '${running}'" >&2
            return 1
        fi
        if [[ "${ref}" =~ ${addon_re} ]] || [[ "${ref}" =~ ${core_re} ]]; then
            sha="${BASH_REMATCH[1]}"
        else
            continue
        fi
        if [ "${sha}" = "${head_sha}" ]; then
            continue
        fi
        if [ "$(( pending + running ))" -eq 0 ]; then
            continue
        fi
        echo "${ref}"
    done
}

# list_testgrid_runs prints "<pending_runs> <running_runs> <ref>" for every run
# whose lowercased ref contains $1 (the API's searchRef does not lowercase its
# input, so $1 must be lowercase). The ref goes last so that `read` keeps it
# whole.
function list_testgrid_runs() {
    local search="$1"
    local page_size=100
    local page=0
    local fetched=0
    local total resp count

    # Callers run this in a command substitution, where set -e is off, so
    # every failure must return explicitly or the loop never ends.
    while :; do
        resp="$(curl "${CURL_OPTS[@]}" "${TESTGRID_API}/api/v1/runs?searchRef=${search}&pageSize=${page_size}&currentPage=${page}")" || return 1
        total="$(echo "${resp}" | jq -r '.total')" || return 1
        count="$(echo "${resp}" | jq -r '.runs | length')" || return 1
        if ! [[ "${total}" =~ ^[0-9]+$ && "${count}" =~ ^[0-9]+$ ]]; then
            echo "unexpected Testgrid runs response: ${resp:0:200}" >&2
            return 1
        fi

        echo "${resp}" | jq -r '.runs[] | "\(.pending_runs) \(.running_runs) \(.id)"' || return 1
        fetched=$((fetched + count))
        if [ "${count}" -eq 0 ] || [ "${fetched}" -ge "${total}" ]; then
            break
        fi
        page=$((page + 1))
    done
}

function cancel_testgrid_ref() {
    local ref="$1"
    curl "${CURL_OPTS[@]}" -w '\n' -X POST "${TESTGRID_API}/v1/ref/${ref}/cancel"
}

function main() {
    require PR_NUMBER "${PR_NUMBER}"
    require PR_HEAD_SHA "${PR_HEAD_SHA}"

    echo "Cancelling stale Testgrid runs for PR #${PR_NUMBER} (head ${PR_HEAD_SHA:0:7})"

    # Rows can repeat when runs shift between pages; dedupe after filtering
    # so the API's newest-first order is kept.
    set -o pipefail
    local refs
    if ! refs="$( { list_testgrid_runs "pr-${PR_NUMBER}-" && list_testgrid_runs "rc-pr${PR_NUMBER}-"; } \
        | stale_testgrid_refs "${PR_NUMBER}" "${PR_HEAD_SHA}" | awk '!seen[$0]++')"; then
        echo "::warning ::failed to list Testgrid runs for PR #${PR_NUMBER}"
        return 1
    fi

    if [ -z "${refs}" ]; then
        echo "No stale Testgrid runs found."
        return 0
    fi

    local ref failed=0
    while IFS= read -r ref; do
        echo "Cancelling ${ref}"
        if ! cancel_testgrid_ref "${ref}"; then
            echo "::warning ::failed to cancel Testgrid run ${ref}"
            failed=1
        fi
    done <<< "${refs}"
    return "${failed}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
