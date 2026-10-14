#!/bin/bash

# Structural guard on .github/workflows/testgrid-pr.yaml's `kurl-util-image`
# job: that job must authenticate to Docker Hub with the existing
# DOCKERHUB_USER / DOCKERHUB_PASSWORD secret, the same credential
# build-image.yaml, deploy-prod.yaml, and deploy-staging.yaml already use.
#
# An earlier revision of this workflow introduced a dedicated
# DOCKERHUB_PR_USER / DOCKERHUB_PR_TOKEN pair to scope this job away from the
# prod-capable credential. That pair was never actually provisioned in the
# repo's secrets (see PR #6173 review feedback), so a run against that
# revision fails docker/login-action outright. Revert to the credential that
# is actually configured until a scoped pair is provisioned and documented.
#
# This test fails against a workflow that references the unprovisioned
# DOCKERHUB_PR_USER / DOCKERHUB_PR_TOKEN pair, and passes once the job uses
# the existing DOCKERHUB_USER / DOCKERHUB_PASSWORD secret.

WORKFLOW="./.github/workflows/testgrid-pr.yaml"

testKurlUtilImageJobUsesProvisionedDockerHubCredential() {
    # Isolate the kurl-util-image job body (next top-level job starts the
    # cutoff) so a secret reference anywhere else in the file can't hide the
    # job-specific check.
    local job_body
    job_body="$(mktemp)"
    awk '/^  kurl-util-image:/{found=1} found && /^  [a-zA-Z0-9_-]+:$/ && !/^  kurl-util-image:$/{exit} found' \
        "${WORKFLOW}" > "${job_body}"

    assertTrue "kurl-util-image job must use the provisioned secrets.DOCKERHUB_USER" \
        "grep -q 'secrets.DOCKERHUB_USER' '${job_body}'"
    assertTrue "kurl-util-image job must use the provisioned secrets.DOCKERHUB_PASSWORD" \
        "grep -q 'secrets.DOCKERHUB_PASSWORD' '${job_body}'"
    assertFalse "kurl-util-image job must not reference the unprovisioned DOCKERHUB_PR_USER secret" \
        "grep -q 'secrets.DOCKERHUB_PR_USER' '${job_body}'"
    assertFalse "kurl-util-image job must not reference the unprovisioned DOCKERHUB_PR_TOKEN secret" \
        "grep -q 'secrets.DOCKERHUB_PR_TOKEN' '${job_body}'"

    rm -f "${job_body}"
}

testKurlUtilImageJobScopesGitHubTokenAndDropsPersistedCredentials() {
    # This job checks out PR-authored content while a Docker Hub credential
    # is logged in (see the test above). Without a job-level `permissions:`
    # block the workflow falls back to the repo default GITHUB_TOKEN scope,
    # and checkout's default `persist-credentials: true` leaves that token
    # sitting in .git/config for anything the retag/build steps run.
    #
    # Strip comment-only lines before asserting: the job's explanatory
    # comments quote `persist-credentials: false` verbatim, so a plain grep
    # over the raw job body would pass even if the real `with:` key were
    # removed from a checkout step.
    local job_body
    job_body="$(mktemp)"
    awk '/^  kurl-util-image:/{found=1} found && /^  [a-zA-Z0-9_-]+:$/ && !/^  kurl-util-image:$/{exit} found' \
        "${WORKFLOW}" | grep -v '^[[:space:]]*#' > "${job_body}"

    assertTrue "kurl-util-image job must declare a minimal permissions block" \
        "grep -q 'permissions:' '${job_body}'"
    assertTrue "kurl-util-image job must set persist-credentials: false on its checkout steps" \
        "grep -q 'persist-credentials: false' '${job_body}'"

    rm -f "${job_body}"
}

testPersistCredentialsGuardIgnoresCommentOnlyMentions() {
    # Reproduces the gap above directly: a job whose ONLY mention of
    # `persist-credentials: false` is inside a comment, with no real
    # checkout step setting the key, must fail the guard rather than pass
    # on the comment text.
    local fixture job_body
    fixture="$(mktemp)"
    job_body="$(mktemp)"
    cat > "${fixture}" <<'EOF'
  kurl-util-image:
    runs-on: ubuntu-24.04
    permissions:
      contents: read
    steps:
      # persist-credentials: false -- this comment describes a step that
      # never actually sets the key below.
      - uses: actions/checkout@v7
        with:
          ref: main
  job2:
    runs-on: ubuntu-24.04
EOF

    awk '/^  kurl-util-image:/{found=1} found && /^  [a-zA-Z0-9_-]+:$/ && !/^  kurl-util-image:$/{exit} found' \
        "${fixture}" | grep -v '^[[:space:]]*#' > "${job_body}"

    assertFalse "a comment-only mention of persist-credentials: false must not satisfy the guard" \
        "grep -q 'persist-credentials: false' '${job_body}'"

    rm -f "${fixture}" "${job_body}"
}

testKurlUtilImageJobCheckOutRetagScriptOnLabelPath() {
    # The retag step always sources bin/retag-and-push-kurl-util-image.sh,
    # so it must exist even on the default (label) path, which otherwise
    # checks out nothing. This exact checkout step was missing in
    # production between 6513d8da4 (credential scoping) and 994be44fa (this
    # fix), breaking every label-triggered run with "No such file or
    # directory" -- pin it so it can't silently regress again.
    local job_body
    job_body="$(mktemp)"
    awk '/^  kurl-util-image:/{found=1} found && /^  [a-zA-Z0-9_-]+:$/ && !/^  kurl-util-image:$/{exit} found' \
        "${WORKFLOW}" > "${job_body}"

    # Split into per-step blocks on the "      - " step marker and require a
    # SINGLE step to contain all three of: an actions/checkout use, the
    # script's sparse-checkout path, and the label-path gate. A looser
    # "appears somewhere in the job body" check (plain grep, or grep -B5 on
    # the script-path line) also passes against the pre-fix job body: the
    # retag-and-push step that *sources* the script carries the same
    # `!inputs.build-kurl-util-image` condition on itself, so it satisfies
    # a proximity check without any checkout step existing at all.
    assertTrue "kurl-util-image job must have a checkout step, gated to the !build-kurl-util-image (label) path, that sparse-checks-out bin/retag-and-push-kurl-util-image.sh" \
        "awk '/^      - /{if (step ~ /uses: actions\\/checkout/ && step ~ /retag-and-push-kurl-util-image\\.sh/ && step ~ /!inputs\\.build-kurl-util-image/) found=1; step=\"\"} {step = step \"\\n\" \$0} END{if (step ~ /uses: actions\\/checkout/ && step ~ /retag-and-push-kurl-util-image\\.sh/ && step ~ /!inputs\\.build-kurl-util-image/) found=1; exit !found}' '${job_body}'"

    rm -f "${job_body}"
}

testJobNameCutoffHandlesDigitsInNextJobName() {
    # 09abd35f4 widened the next-job cutoff pattern from [a-zA-Z_-]+ to
    # [a-zA-Z0-9_-]+ specifically so a next-job name containing a digit still
    # ends the kurl-util-image job extraction -- otherwise that job's body
    # leaks into the extracted block and silently defeats every assertion
    # above. The real workflow's actual next job (build-matrix) has no
    # digits, so none of the tests above exercise this boundary. Build a
    # synthetic fixture with a digit-bearing next-job name instead.
    local fixture job_body
    fixture="$(mktemp)"
    job_body="$(mktemp)"
    cat > "${fixture}" <<'EOF'
  kurl-util-image:
    runs-on: ubuntu-24.04
    steps:
      - run: echo building
  job2:
    runs-on: ubuntu-24.04
    steps:
      - run: echo "${{ secrets.SOME_OTHER_SECRET }}"
EOF

    awk '/^  kurl-util-image:/{found=1} found && /^  [a-zA-Z0-9_-]+:$/ && !/^  kurl-util-image:$/{exit} found' \
        "${fixture}" > "${job_body}"

    assertFalse "the digit-bearing next job's body must not leak into the extracted kurl-util-image job" \
        "grep -q 'SOME_OTHER_SECRET' '${job_body}'"

    rm -f "${fixture}" "${job_body}"
}

testKurlUtilImageJobPinsLabelPathCheckoutToTrustedRef() {
    # BLOCKING-1 (PR #6173 review round 5): the label-path checkout that
    # sparse-checks-out bin/retag-and-push-kurl-util-image.sh had no `ref:`
    # at all, so it defaulted to the triggering ref -- the PR's own merge
    # commit -- then docker/login-action logs in right after it, and the
    # retag step sources that PR-authored script while authenticated. A
    # run-testgrid-labeled PR (labelable at Triage access) that edits that
    # script runs it with a prod-capable Docker Hub credential. Pin the
    # checkout to the repository's default branch so only a maintainer
    # merging to it can change what that script does.
    local job_body
    job_body="$(mktemp)"
    awk '/^  kurl-util-image:/{found=1} found && /^  [a-zA-Z0-9_-]+:$/ && !/^  kurl-util-image:$/{exit} found' \
        "${WORKFLOW}" > "${job_body}"

    assertTrue "kurl-util-image job must have a checkout step, gated to the !build-kurl-util-image (label) path, that pins ref to the repository default branch" \
        "awk '/^      - /{if (step ~ /uses: actions\\/checkout/ && step ~ /retag-and-push-kurl-util-image\\.sh/ && step ~ /!inputs\\.build-kurl-util-image/ && step ~ /github\\.event\\.repository\\.default_branch/) found=1; step=\"\"} {step = step \"\\n\" \$0} END{if (step ~ /uses: actions\\/checkout/ && step ~ /retag-and-push-kurl-util-image\\.sh/ && step ~ /!inputs\\.build-kurl-util-image/ && step ~ /github\\.event\\.repository\\.default_branch/) found=1; exit !found}' '${job_body}'"

    rm -f "${job_body}"
}

testKurlUtilImageJobDispatchBranchCheckoutIsAdditiveNotAFallback() {
    # PR #6173 review round 7 (doomer-ai): an earlier revision made the
    # default-branch checkout's `ref:` fall back to inputs.branch on
    # workflow_dispatch. inputs.branch can be ANY pre-existing branch,
    # including one that predates bin/retag-and-push-kurl-util-image.sh
    # entirely -- a sparse-checkout whose pattern matches nothing on that ref
    # succeeds with an empty result rather than failing, so that fallback
    # left the retag step's `source` with no file on an old branch, dying
    # with "No such file or directory".
    #
    # The fix checks out the dispatched branch's own copy into a SEPARATE
    # directory (so it can't silently blank out the default-branch copy) and
    # only overwrites the default-branch copy via a later step when a file
    # actually landed there. Guard against the single-step fallback pattern
    # regressing back in.
    local job_body
    job_body="$(mktemp)"
    awk '/^  kurl-util-image:/{found=1} found && /^  [a-zA-Z0-9_-]+:$/ && !/^  kurl-util-image:$/{exit} found' \
        "${WORKFLOW}" > "${job_body}"

    assertFalse "the retag-script checkout must not fall back to inputs.branch in its own ref (that silently empties the checkout on branches that predate the script)" \
        "awk '/^      - /{if (step ~ /uses: actions\\/checkout/ && step ~ /retag-and-push-kurl-util-image\\.sh/ && step ~ /ref: \\$\\{\\{ github\\.event_name == .workflow_dispatch. && inputs\\.branch/) found=1; step=\"\"} {step = step \"\\n\" \$0} END{if (step ~ /uses: actions\\/checkout/ && step ~ /retag-and-push-kurl-util-image\\.sh/ && step ~ /ref: \\$\\{\\{ github\\.event_name == .workflow_dispatch. && inputs\\.branch/) found=1; exit !found}' '${job_body}'"

    assertTrue "kurl-util-image job must have a SEPARATE workflow_dispatch-only checkout of the dispatched branch's own retag script into its own path" \
        "awk '/^      - /{if (step ~ /uses: actions\\/checkout/ && step ~ /retag-and-push-kurl-util-image\\.sh/ && step ~ /github\\.event_name == .workflow_dispatch./ && step ~ /ref: \\$\\{\\{ inputs\\.branch \\}\\}/ && step ~ /path:/) found=1; step=\"\"} {step = step \"\\n\" \$0} END{if (step ~ /uses: actions\\/checkout/ && step ~ /retag-and-push-kurl-util-image\\.sh/ && step ~ /github\\.event_name == .workflow_dispatch./ && step ~ /ref: \\$\\{\\{ inputs\\.branch \\}\\}/ && step ~ /path:/) found=1; exit !found}' '${job_body}'"

    assertTrue "kurl-util-image job must have a step that copies the dispatched branch's retag script over the default copy only when it exists" \
        "grep -q 'prefer the dispatched branch' '${job_body}'"

    rm -f "${job_body}"
}

testHeaderDoesNotDocumentUnprovisionedDockerHubCredential() {
    # Scope the grep to the header comment block (everything before the
    # top-level `on:` trigger section) so this only checks the provisioning
    # doc itself.
    local header
    header="$(mktemp)"
    awk '/^on:/{exit} {print}' "${WORKFLOW}" > "${header}"

    assertFalse "REQUIRED provisioning section must not document the unprovisioned DOCKERHUB_PR_USER credential" \
        "grep -q 'DOCKERHUB_PR_USER' '${header}'"

    rm -f "${header}"
}

# shellcheck source=/dev/null
. shunit2
