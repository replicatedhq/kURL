#!/bin/bash

# This file relies on bash's 0-indexed arrays (block[0]/rewritten[0]). Under
# zsh (1-indexed arrays), those index references silently resolve to the
# wrong element instead of erroring, which corrupts the rewritten spec file
# instead of failing loudly. Refuse to run at all outside bash.
if [ -z "${BASH_VERSION:-}" ]; then
    echo "testgrid-pr-spec.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi

# testgrid_pr_patch_spec rewrites a Testgrid spec file in place for a
# testgrid-pr.yaml run: it pins the empty installerVersion placeholder to the
# run's RC version tag, and points installerApiEndpoint at the staging host
# -- scoped to each top-level spec entry (`- name: ...`) individually.
#
# testgrid-pr.yaml publishes every build (label or workflow_dispatch) only
# under the per-PR RC prefix s3://kurl-sh/staging/<rc-tag>/ -- it never
# promotes to dist/ and never touches the shared staging/VERSION pointer
# (see testgrid/specs/README.md). An entry whose installerVersion is the
# empty RC placeholder resolves against this run's RC build, so its
# installerApiEndpoint must point at the staging host or the install phase
# 404s before kubeadm ever runs (kURL#6171: 10/10 cluster_not_ready, while
# the identical artifact resolves under https://s3.kurl.sh/staging/ -- the
# raw object-storage host for the RC tarball/bundle, a different real host
# from https://staging.kurl.sh, the install-time API endpoint this function
# rewrites installerApiEndpoint to). That entry may have no
# installerApiEndpoint field at all (it is inserted), or an existing one (it
# is rewritten).
#
# An entry with a real, already-released installerVersion pin (no empty
# placeholder) is left entirely untouched, including its
# installerApiEndpoint -- those entries are not part of this RC build and
# rewriting their endpoint to staging would point an already-released,
# never-restaged version at a staging prefix it was never published under
# (review ku-li93 BLOCKING-2).
#
# Scoped to testgrid-pr.yaml's own ephemeral checkout of the spec file, this
# leaves every other workflow's use of these same committed spec files
# (deploy-staging.yaml, deploy-prod.yaml, cron-*) unchanged.
function testgrid_pr_patch_spec() {
    local spec_file="$1"
    local version_tag="$2"

    local -a out=()
    local -a block=()
    local has_placeholder=0
    local has_endpoint=0
    local failed=0

    _testgrid_pr_flush_block() {
        local line
        local -a rewritten=()
        # The entry's field-level indent (e.g. "  " or "    ") is whatever
        # the first field line after "- name:" uses -- every top-level field
        # in the entry (installerApiEndpoint, installerSpec, airgap, ...)
        # shares it. Falls back to the conventional 2 spaces for a block that
        # is only the "- name:" line.
        local entry_indent="  "
        if [ "${#block[@]}" -gt 1 ]; then
            local second="${block[1]}"
            entry_indent="${second%%[^[:space:]]*}"
        fi
        for line in "${block[@]}"; do
            if [ "$has_placeholder" -eq 1 ] && [[ "$line" == *'installerVersion: ""'* ]]; then
                line="${line//installerVersion: \"\"/installerVersion: \"${version_tag}\"}"
            fi
            if [ "$has_placeholder" -eq 1 ] && [[ "$line" =~ ^([[:space:]]*)installerApiEndpoint: ]]; then
                line="${BASH_REMATCH[1]}installerApiEndpoint: https://staging.kurl.sh"
            fi
            rewritten+=("$line")
        done
        if [ "$has_placeholder" -eq 1 ] && [ "$has_endpoint" -eq 0 ] && [ "${#rewritten[@]}" -gt 0 ]; then
            local first="${rewritten[0]}"
            rewritten=("$first" "${entry_indent}installerApiEndpoint: https://staging.kurl.sh" "${rewritten[@]:1}")
        fi
        if [ "$has_placeholder" -eq 1 ]; then
            local ok=0
            for line in "${rewritten[@]}"; do
                [[ "$line" =~ ^[[:space:]]*installerApiEndpoint:\ https://staging\.kurl\.sh$ ]] && ok=1
            done
            if [ "$ok" -ne 1 ]; then
                echo "::error::testgrid_pr_patch_spec: failed to ensure installerApiEndpoint: https://staging.kurl.sh for entry starting '${block[0]}'" >&2
                failed=1
            fi
        fi
        out+=("${rewritten[@]}")
        block=()
        has_placeholder=0
        has_endpoint=0
    }

    local line
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" == "- name:"* ]]; then
            if [ "${#block[@]}" -gt 0 ]; then
                _testgrid_pr_flush_block
            fi
        fi
        block+=("$line")
        if [[ "$line" == *'installerVersion: ""'* ]]; then
            has_placeholder=1
        fi
        if [[ "$line" =~ ^[[:space:]]*installerApiEndpoint: ]]; then
            has_endpoint=1
        fi
    done < "${spec_file}"
    if [ "${#block[@]}" -gt 0 ]; then
        _testgrid_pr_flush_block
    fi

    if [ "$failed" -eq 1 ]; then
        return 1
    fi

    printf '%s\n' "${out[@]}" > "${spec_file}.tmp"
    mv "${spec_file}.tmp" "${spec_file}"
}
