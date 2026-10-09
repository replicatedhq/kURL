#!/bin/bash

# Tests for testgrid_pr_patch_spec() in testgrid-pr-spec.sh.
#
# testgrid-pr.yaml publishes PR/RC builds only under the per-PR RC prefix
# s3://kurl-sh/staging/<rc-tag>/ -- it never promotes to dist/ or touches the
# shared staging/VERSION pointer (see testgrid/specs/README.md). An entry
# whose installerVersion is the empty RC placeholder must resolve against the
# staging host (inserted if absent, rewritten if present) or its install
# phase 404s for these runs (kURL#6171's first testgrid-pr.yaml run: 10/10
# cluster_not_ready, confirmed via
# `curl https://kurl.sh/version/<rc-tag>/<hash>` -> 404, while the same
# artifact 200s under https://s3.kurl.sh/staging/<rc-tag>/... -- the raw
# object-storage host for the tarball, a different real host from
# https://staging.kurl.sh, the install-time API endpoint
# testgrid_pr_patch_spec rewrites installerApiEndpoint to below). An entry with
# a real, already-released installerVersion pin (no empty placeholder) must
# be left completely untouched, including its own installerApiEndpoint --
# that entry is not part of this RC build and was never republished under a
# staging prefix.

testScriptRefusesToSourceUnderNonBashShell() {
    # Under zsh, arrays are 1-indexed, so block[0]/rewritten[0] silently
    # resolve to the wrong element instead of erroring -- this corrupts the
    # rewritten spec instead of failing loudly (kURL#6172 review LOW-6). The
    # script must refuse to run at all outside bash.
    #
    # None of the five docker-test-shell images carry zsh, and "exercise it
    # with a non-bash shell that's already there" doesn't work either: the
    # RHEL/oraclelinux images symlink /bin/sh straight to bash, so BASH_VERSION
    # is still set when invoked as "sh" (only the Ubuntu images' dash lacks
    # it), which would make this test's assertions diverge by image instead of
    # running the same way everywhere. So exercise the guard's actual
    # condition directly -- unset BASH_VERSION inside a bash subshell before
    # sourcing -- which reproduces exactly what the guard checks
    # (`[ -z "${BASH_VERSION:-}" ]`) deterministically on every CI image,
    # without an optional interpreter that can make the test silently skip
    # (review ku-uiz0 LOW-4).
    local spec
    spec="$(mktemp)"
    cat > "${spec}" <<'EOF'
- name: "example"
  installerApiEndpoint: https://kurl.sh
  installerSpec:
    kurl:
      installerVersion: ""
EOF
    local before
    before="$(cat "${spec}")"

    local out rc
    out="$(bash -c 'unset BASH_VERSION; source ./bin/testgrid-pr-spec.sh && testgrid_pr_patch_spec "$1" "$2"' _ "${spec}" "v2026.10.01-0-rc-pr6171-a25c664" 2>&1)"
    rc=$?

    assertEquals "1" "${rc}"
    assertTrue "expected a 'requires bash' error, got: ${out}" \
        "printf '%s' \"${out}\" | grep -q 'requires bash'"
    assertEquals "spec file must be left untouched when the guard fires" \
        "${before}" "$(cat "${spec}")"

    rm -f "${spec}"
}

# shellcheck source=testgrid-pr-spec.sh
. ./bin/testgrid-pr-spec.sh

testPatchSpecRewritesApiEndpointToStaging() {
    local spec
    spec="$(mktemp)"
    cat > "${spec}" <<'EOF'
- name: "example"
  installerApiEndpoint: https://kurl.sh
  installerSpec:
    kurl:
      installerVersion: ""
EOF

    testgrid_pr_patch_spec "${spec}" "v2026.10.01-0-rc-pr6171-a25c664"

    assertEquals "1" "$(grep -c 'installerApiEndpoint: https://staging.kurl.sh' "${spec}")"
    assertEquals "0" "$(grep -cE '^\s*installerApiEndpoint: https://kurl\.sh$' "${spec}")"

    rm -f "${spec}"
}

testPatchSpecPinsInstallerVersion() {
    local spec
    spec="$(mktemp)"
    cat > "${spec}" <<'EOF'
- name: "example"
  installerApiEndpoint: https://kurl.sh
  installerSpec:
    kurl:
      installerVersion: ""
EOF

    testgrid_pr_patch_spec "${spec}" "v2026.10.01-0-rc-pr6171-a25c664"

    assertEquals "1" "$(grep -c 'installerVersion: "v2026.10.01-0-rc-pr6171-a25c664"' "${spec}")"

    rm -f "${spec}"
}

testPatchSpecRewritesEveryOccurrence() {
    local spec
    spec="$(mktemp)"
    cat > "${spec}" <<'EOF'
- name: "one"
  installerApiEndpoint: https://kurl.sh
  installerSpec:
    kurl:
      installerVersion: ""
- name: "two"
  installerApiEndpoint: https://kurl.sh
  installerSpec:
    kurl:
      installerVersion: ""
EOF

    testgrid_pr_patch_spec "${spec}" "v2026.10.01-0-rc-pr6171-a25c664"

    assertEquals "2" "$(grep -c 'installerApiEndpoint: https://staging.kurl.sh' "${spec}")"
    assertEquals "2" "$(grep -c 'installerVersion: "v2026.10.01-0-rc-pr6171-a25c664"' "${spec}")"

    rm -f "${spec}"
}

testPatchSpecLeavesStagingHostAlone() {
    # A spec field that already points at the staging host (e.g. a hand-edited
    # dispatch spec) must not be touched or double-rewritten.
    local spec
    spec="$(mktemp)"
    cat > "${spec}" <<'EOF'
- name: "example"
  installerApiEndpoint: https://staging.kurl.sh
  installerSpec:
    kurl:
      installerVersion: ""
EOF

    testgrid_pr_patch_spec "${spec}" "v2026.10.01-0-rc-pr6171-a25c664"

    assertEquals "1" "$(grep -c 'installerApiEndpoint: https://staging.kurl.sh' "${spec}")"

    rm -f "${spec}"
}

testPatchSpecSecondPassIsIdempotent() {
    # Running testgrid_pr_patch_spec a second time on its own output (e.g. a
    # retried workflow step against the same checkout) must be a true no-op:
    # not only the staging-host count, but the installerVersion pin count and
    # every other line in the file must be unperturbed by the second pass
    # (review ku-fxzd LOW-3 -- the prior version of this test only asserted
    # the staging-host count stayed at 1).
    local spec
    spec="$(mktemp)"
    cat > "${spec}" <<'EOF'
- name: "historical pin"
  installerApiEndpoint: https://kurl.sh
  installerSpec:
    kurl:
      installerVersion: "v2024.07.02-0"
- name: "rc placeholder"
  installerSpec:
    kurl:
      installerVersion: ""
EOF

    testgrid_pr_patch_spec "${spec}" "v2026.10.01-0-rc-pr6171-a25c664"
    local first_pass
    first_pass="$(cat "${spec}")"

    testgrid_pr_patch_spec "${spec}" "v2026.10.01-0-rc-pr6171-a25c664"

    assertEquals "second pass must leave every line exactly as the first pass produced it" \
        "${first_pass}" "$(cat "${spec}")"
    assertEquals "1" "$(grep -c '^  installerApiEndpoint: https://staging.kurl.sh$' "${spec}")"
    assertEquals "1" "$(grep -c 'installerVersion: "v2026.10.01-0-rc-pr6171-a25c664"' "${spec}")"
    assertEquals "1" "$(grep -c '^  installerApiEndpoint: https://kurl\.sh$' "${spec}")"
    assertEquals "1" "$(grep -c 'installerVersion: "v2024.07.02-0"' "${spec}")"

    rm -f "${spec}"
}

testPatchSpecInsertsMissingApiEndpoint() {
    # An entry with the empty-version RC placeholder but no
    # installerApiEndpoint field at all (e.g. the real deploy.yaml airgap
    # entry) must have the field inserted, not silently skipped (review
    # ku-z32a BLOCKING-1).
    local spec
    spec="$(mktemp)"
    cat > "${spec}" <<'EOF'
- name: "airgap upgrade"
  airgap: true
  installerSpec:
    kubernetes:
      version: 1.31.x
    kurl:
      installerVersion: ""
  upgradeSpec:
    kubernetes:
      version: 1.36.x
    kurl:
      installerVersion: ""
EOF

    testgrid_pr_patch_spec "${spec}" "v2026.10.01-0-rc-pr6171-a25c664"

    assertEquals "1" "$(grep -c '^  installerApiEndpoint: https://staging.kurl.sh$' "${spec}")"
    assertEquals "2" "$(grep -c 'installerVersion: "v2026.10.01-0-rc-pr6171-a25c664"' "${spec}")"

    rm -f "${spec}"
}

testPatchSpecLeavesHistoricalPinEntryUntouched() {
    # An entry with a real, already-released installerVersion pin (no empty
    # placeholder) is not part of this RC build and must be left completely
    # untouched, including its own installerApiEndpoint, even though it is a
    # literal "https://kurl.sh" match (review ku-li93 BLOCKING-2).
    local spec
    spec="$(mktemp)"
    cat > "${spec}" <<'EOF'
- name: "historical pin"
  installerApiEndpoint: https://kurl.sh
  installerSpec:
    kurl:
      installerVersion: "v2024.07.02-0"
EOF

    testgrid_pr_patch_spec "${spec}" "v2026.10.01-0-rc-pr6171-a25c664"

    assertEquals "1" "$(grep -c '^  installerApiEndpoint: https://kurl\.sh$' "${spec}")"
    assertEquals "1" "$(grep -c 'installerVersion: "v2024.07.02-0"' "${spec}")"
    assertEquals "0" "$(grep -c 'staging.kurl.sh' "${spec}")"

    rm -f "${spec}"
}

testPatchSpecMixedFileOnlyTouchesPlaceholderEntry() {
    # The real deploy.yaml shape: one historical-pin entry (non-empty
    # installerVersion, explicit prod installerApiEndpoint) followed by one
    # RC-placeholder entry (empty installerVersion, no installerApiEndpoint
    # field). Only the second entry's fields may change.
    local spec
    spec="$(mktemp)"
    cat > "${spec}" <<'EOF'
- name: "historical pin"
  installerApiEndpoint: https://kurl.sh
  installerSpec:
    kurl:
      installerVersion: "v2024.07.02-0"
- name: "rc placeholder"
  installerSpec:
    kurl:
      installerVersion: ""
EOF

    testgrid_pr_patch_spec "${spec}" "v2026.10.01-0-rc-pr6171-a25c664"

    assertEquals "1" "$(grep -c '^  installerApiEndpoint: https://kurl\.sh$' "${spec}")"
    assertEquals "1" "$(grep -c 'installerVersion: "v2024.07.02-0"' "${spec}")"
    assertEquals "1" "$(grep -c '^  installerApiEndpoint: https://staging.kurl.sh$' "${spec}")"
    assertEquals "1" "$(grep -c 'installerVersion: "v2026.10.01-0-rc-pr6171-a25c664"' "${spec}")"

    rm -f "${spec}"
}

testPatchSpecDetectsAndRewritesFourSpaceIndentedEndpoint() {
    # installerApiEndpoint detection/insertion must be scoped to the entry's
    # own field indent level, not hardcoded to 2 spaces (review ku-fxzd
    # LOW-9). A spec whose top-level fields sit at 4 spaces must still have
    # its existing installerApiEndpoint found and rewritten at that same
    # indent -- not duplicated with a second, 2-space-indented field.
    local spec
    spec="$(mktemp)"
    cat > "${spec}" <<'EOF'
- name: "example"
    installerApiEndpoint: https://kurl.sh
    installerSpec:
        kurl:
            installerVersion: ""
EOF

    testgrid_pr_patch_spec "${spec}" "v2026.10.01-0-rc-pr6171-a25c664"

    assertEquals "1" "$(grep -c '^    installerApiEndpoint: https://staging.kurl.sh$' "${spec}")"
    assertEquals "0" "$(grep -cE '^\s*installerApiEndpoint: https://kurl\.sh$' "${spec}")"
    assertEquals "1" "$(grep -c 'installerApiEndpoint:' "${spec}")"

    rm -f "${spec}"
}

testPatchSpecAgainstRealDeploySpecOnlyTouchesIntendedEntries() {
    # Run against a copy of the actual committed testgrid/specs/deploy.yaml,
    # not just synthetic fixtures (review ku-fxzd LOW-7). As of this writing
    # that file has 7 entries: 2 historical pins (real installerVersion,
    # explicit https://kurl.sh installerApiEndpoint, no installerApiEndpoint
    # field at all) and 1 airgap entry with two RC placeholders (installerSpec
    # and upgradeSpec) sharing one "- name:" block and no installerApiEndpoint
    # field (review ku-fxzd LOW-5's real two-shape fixture).
    if [ ! -f testgrid/specs/deploy.yaml ]; then
        startSkipping
        return
    fi

    local spec
    spec="$(mktemp)"
    cp testgrid/specs/deploy.yaml "${spec}"

    local before_entries before_lines before_endpoints
    before_entries="$(grep -c '^- name:' "${spec}")"
    before_lines="$(wc -l < "${spec}" | tr -d '[:space:]')"
    before_endpoints="$(grep -c 'installerApiEndpoint:' "${spec}")"

    testgrid_pr_patch_spec "${spec}" "v2026.10.01-0-rc-pr6171-a25c664"

    assertEquals "patching must not add or remove entries" \
        "${before_entries}" "$(grep -c '^- name:' "${spec}")"

    # Only the airgap entry's two placeholders were rewritten, and it gained
    # exactly one inserted installerApiEndpoint (not one per placeholder).
    assertEquals "2" "$(grep -c 'installerVersion: "v2026.10.01-0-rc-pr6171-a25c664"' "${spec}")"
    assertEquals "0" "$(grep -c 'installerVersion: ""' "${spec}")"
    assertEquals "1" "$(grep -c '^  installerApiEndpoint: https://staging.kurl.sh$' "${spec}")"

    # The 2 historical-pin entries are completely untouched.
    assertEquals "2" "$(grep -c '^  installerApiEndpoint: https://kurl\.sh$' "${spec}")"
    assertEquals "2" "$(grep -c 'installerVersion: "v2024.07.02-0"' "${spec}")"

    # Structural sanity without a YAML parser (the docker-test-shell
    # containers this suite runs in -- rhel-7/8/9, ubuntu-20.04/22.04 -- have
    # no interpreter installed in common, so there's nothing to parse with):
    # exactly one line was added (the single inserted installerApiEndpoint),
    # and the total installerApiEndpoint count grew by exactly that one --
    # proving no duplicate key or stray/lost line, which is the corruption
    # shape a miscomputed array index (review LOW-6) or a hardcoded indent
    # match (review LOW-9) could actually produce against this file.
    assertEquals "patching must add exactly one line" \
        "$((before_lines + 1))" "$(wc -l < "${spec}" | tr -d '[:space:]')"
    assertEquals "installerApiEndpoint count must grow by exactly one" \
        "$((before_endpoints + 1))" "$(grep -c 'installerApiEndpoint:' "${spec}")"

    rm -f "${spec}"
}

testFlushBlockSafetyNetCatchesMissingEndpointInsertion() {
    # _testgrid_pr_flush_block's invariant check (bin/testgrid-pr-spec.sh:77-86)
    # is the last line of defense against a rewrite bug that silently drops
    # the installerApiEndpoint insertion it just claimed to make. Force that
    # branch by sourcing a copy of the script with the insertion step (the
    # "has_placeholder && !has_endpoint" branch that synthesizes the missing
    # line) stubbed out to a no-op, so a placeholder entry with no
    # installerApiEndpoint field reaches the invariant check still missing
    # one -- proving the safety net actually fires and the spec file is left
    # untouched, instead of silently writing a corrupted spec.
    #
    # TDD: deleting the invariant check (the "if [ "$has_placeholder" -eq 1 ]"
    # block that sets failed=1) from bin/testgrid-pr-spec.sh makes this test
    # fail -- the stubbed insertion step would then return 0 and the caller
    # would never know the installerApiEndpoint was never added.
    local broken_script
    broken_script="$(mktemp)"
    sed 's/if \[ "\$has_placeholder" -eq 1 \] && \[ "\$has_endpoint" -eq 0 \] && \[ "\${#rewritten\[@\]}" -gt 0 \]; then/if false; then/' \
        ./bin/testgrid-pr-spec.sh > "${broken_script}"

    local spec
    spec="$(mktemp)"
    cat > "${spec}" <<'EOF'
- name: "airgap upgrade"
  installerSpec:
    kurl:
      installerVersion: ""
EOF
    local before
    before="$(cat "${spec}")"

    local out rc
    out="$(bash -c 'source "$1" && testgrid_pr_patch_spec "$2" "$3"' \
        _ "${broken_script}" "${spec}" "v2026.10.01-0-rc-pr6171-a25c664" 2>&1)"
    rc=$?

    assertEquals "1" "${rc}"
    assertTrue "expected the invariant-failure log line, got: ${out}" \
        "printf '%s' \"${out}\" | grep -q 'failed to ensure installerApiEndpoint'"
    assertEquals "spec file must be left untouched when the safety net fires" \
        "${before}" "$(cat "${spec}")"

    rm -f "${broken_script}" "${spec}"
}

testPatchSpecInsertsFourSpaceIndentedEndpointAtEntryLevel() {
    # Same as above, but for the insert path: an entry with no
    # installerApiEndpoint field at all, at a non-default 4-space entry
    # indent, must get the field inserted at that same indent.
    local spec
    spec="$(mktemp)"
    cat > "${spec}" <<'EOF'
- name: "example"
    installerSpec:
        kurl:
            installerVersion: ""
EOF

    testgrid_pr_patch_spec "${spec}" "v2026.10.01-0-rc-pr6171-a25c664"

    assertEquals "1" "$(grep -c '^    installerApiEndpoint: https://staging.kurl.sh$' "${spec}")"

    rm -f "${spec}"
}

# shellcheck source=/dev/null
. shunit2
