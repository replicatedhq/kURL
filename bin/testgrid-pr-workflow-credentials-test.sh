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
    local job_body
    job_body="$(mktemp)"
    awk '/^  kurl-util-image:/{found=1} found && /^  [a-zA-Z0-9_-]+:$/ && !/^  kurl-util-image:$/{exit} found' \
        "${WORKFLOW}" > "${job_body}"

    assertTrue "kurl-util-image job must declare a minimal permissions block" \
        "grep -q 'permissions:' '${job_body}'"
    assertTrue "kurl-util-image job must set persist-credentials: false on its checkout steps" \
        "grep -q 'persist-credentials: false' '${job_body}'"

    rm -f "${job_body}"
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
