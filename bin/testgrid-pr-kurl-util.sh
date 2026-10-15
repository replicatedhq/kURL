#!/bin/bash

# testgrid_pr_kurl_util_image resolves the kurl-util image tag that a
# testgrid-pr.yaml run's generated installer templates (install.tmpl,
# join.tmpl, upgrade.tmpl, tasks.tmpl) will reference at install time.
#
# kurl.sh renders those templates server-side using the same convention every
# real release relies on: it fills KURL_UTIL_IMAGE with
# replicated/kurl-util:<installerVersion> -- the exact per-version tag
# deploy-staging.yaml's kurl-util-image job always pushes (build :alpha,
# `docker tag` it to the release's VERSION_TAG, push both). There is no
# server-side way to tell it to use :alpha for one specific version instead.
#
# A label/default testgrid-pr run that skips its own branch-specific rebuild
# (build-kurl-util-image=false) must still publish that same versioned tag --
# by retagging and pushing the existing :alpha -- or every instance's
# kurlnet-client/kurlnet-server pods ErrImagePull before any scenario runs
# (kURL#6188). So the resolved image is always the versioned tag regardless
# of build-kurl-util-image; what differs (handled by the workflow's
# kurl-util-image job, not this function) is whether a fresh image needs to
# be BUILT (true) or the existing :alpha just needs to be retagged and
# pushed (false).
function testgrid_pr_kurl_util_image() {
    local version_tag="$1"
    echo "replicated/kurl-util:${version_tag}"
}
