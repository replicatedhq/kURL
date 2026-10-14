#!/bin/bash

# Structural guard on .github/workflows/testgrid-pr.yaml's `kurl-util-image`
# job: that job runs on a plain `label: run-testgrid` trigger (Triage-level
# access, not maintainer-only -- see the workflow's own header) and checks
# out the PR's own ref, so the `retag and push the existing alpha image under
# the RC tag` step sources bin/retag-and-push-kurl-util-image.sh *from the
# PR's branch* while Docker Hub credentials are already logged in.
#
# If that job's docker/login-action reuses the same DOCKERHUB_USER /
# DOCKERHUB_PASSWORD secret that deploy-prod.yaml uses to publish real
# releases, a PR that edits the retag script (e.g. to read
# ~/.docker/config.json and exfiltrate it, or to push an extra tag) runs
# with a prod-capable credential -- not the scoped, PR-only credential the
# workflow's AWS path already requires (see the header's "REQUIRED
# provisioning" section, point 1). The testgrid-pr environment's required
# reviewers gate *that a run starts*, not that the diff was re-reviewed, so
# it is not a substitute for scoping the credential itself.
#
# This test fails against a workflow that reuses the prod Docker Hub secret
# for that job, and passes once it is switched to a dedicated,
# least-privilege DOCKERHUB_PR_USER / DOCKERHUB_PR_TOKEN pair.

WORKFLOW="./.github/workflows/testgrid-pr.yaml"

testKurlUtilImageJobDoesNotReuseProdDockerHubCredential() {
    # Isolate the kurl-util-image job body (next top-level job starts the
    # cutoff) so a prod-secret reference anywhere else in the file -- there
    # is none today, but this keeps the assertion scoped to the job that
    # actually runs PR-authored code under docker login -- can't hide the
    # job-specific check.
    local job_body
    job_body="$(mktemp)"
    awk '/^  kurl-util-image:/{found=1} found && /^  [a-zA-Z0-9_-]+:$/ && !/^  kurl-util-image:$/{exit} found' \
        "${WORKFLOW}" > "${job_body}"

    assertFalse "kurl-util-image job must not reference the prod secrets.DOCKERHUB_USER" \
        "grep -q 'secrets.DOCKERHUB_USER' '${job_body}'"
    assertFalse "kurl-util-image job must not reference the prod secrets.DOCKERHUB_PASSWORD" \
        "grep -q 'secrets.DOCKERHUB_PASSWORD' '${job_body}'"
    assertTrue "kurl-util-image job must use a dedicated, scoped DOCKERHUB_PR_USER secret" \
        "grep -q 'secrets.DOCKERHUB_PR_USER' '${job_body}'"
    assertTrue "kurl-util-image job must use a dedicated, scoped DOCKERHUB_PR_TOKEN secret" \
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

testHeaderDocumentsScopedDockerHubCredentialRequirement() {
    # Scope the grep to the header comment block (everything before the
    # top-level `on:` trigger section) so this only passes if the
    # provisioning doc itself mentions the credential -- the job steps
    # further down also reference DOCKERHUB_PR_USER, which would make an
    # unscoped grep pass even if the header section were deleted.
    local header
    header="$(mktemp)"
    awk '/^on:/{exit} {print}' "${WORKFLOW}" > "${header}"

    assertTrue "REQUIRED provisioning section must document a scoped Docker Hub credential, same as the AWS one" \
        "grep -q 'DOCKERHUB_PR_USER' '${header}'"

    rm -f "${header}"
}

# shellcheck source=/dev/null
. shunit2
