#!/bin/bash

# Tests for testgrid_pr_patch_spec() in testgrid-pr-spec.sh.
#
# testgrid-pr.yaml publishes PR/RC builds only under the per-PR RC prefix
# s3://kurl-sh/staging/<rc-tag>/ -- it never promotes to dist/ or touches the
# shared staging/VERSION pointer (see testgrid/specs/README.md). A spec whose
# installerApiEndpoint is left at the default https://kurl.sh (prod, resolves
# only from dist/) 404s on every install phase for these runs (kURL#6171's
# first testgrid-pr.yaml run: 10/10 cluster_not_ready, confirmed via
# `curl https://kurl.sh/version/<rc-tag>/<hash>` -> 404, while the same
# artifact 200s under https://s3.kurl.sh/staging/<rc-tag>/...). This guards
# that testgrid-pr.yaml always rewrites installerApiEndpoint to the staging
# host before queuing, while leaving every other field (and every other
# workflow's own copy of the spec) untouched.

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

# shellcheck source=/dev/null
. shunit2
