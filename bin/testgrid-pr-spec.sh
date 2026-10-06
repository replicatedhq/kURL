#!/bin/bash

# testgrid_pr_patch_spec rewrites a Testgrid spec file in place for a
# testgrid-pr.yaml run: it pins the empty installerVersion placeholder to the
# run's RC version tag, and points installerApiEndpoint at the staging host.
#
# testgrid-pr.yaml publishes every build (label or workflow_dispatch) only
# under the per-PR RC prefix s3://kurl-sh/staging/<rc-tag>/ -- it never
# promotes to dist/ and never touches the shared staging/VERSION pointer
# (see testgrid/specs/README.md). The spec's default installerApiEndpoint,
# https://kurl.sh, only resolves installers from dist/, so every install
# phase 404s before kubeadm ever runs (kURL#6171: 10/10 cluster_not_ready,
# while the identical artifact resolves under https://s3.kurl.sh/staging/).
# Rewriting the endpoint here, scoped to testgrid-pr.yaml's own ephemeral
# checkout of the spec file, leaves every other workflow's use of these same
# committed spec files (deploy-staging.yaml, deploy-prod.yaml, cron-*)
# unchanged.
function testgrid_pr_patch_spec() {
    local spec_file="$1"
    local version_tag="$2"

    sed -i.bak \
        -e "s/installerVersion: \"\"/installerVersion: \"${version_tag}\"/g" \
        -e "s#installerApiEndpoint: https://kurl\.sh#installerApiEndpoint: https://staging.kurl.sh#g" \
        "${spec_file}"
    rm -f "${spec_file}.bak"
}
