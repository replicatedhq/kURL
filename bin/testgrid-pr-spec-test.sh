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
# artifact 200s under https://s3.kurl.sh/staging/<rc-tag>/...). An entry with
# a real, already-released installerVersion pin (no empty placeholder) must
# be left completely untouched, including its own installerApiEndpoint --
# that entry is not part of this RC build and was never republished under a
# staging prefix.

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

# shellcheck source=/dev/null
. shunit2
