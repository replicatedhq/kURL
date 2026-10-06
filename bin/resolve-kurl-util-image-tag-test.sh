#!/bin/bash

# Tests for resolve_kurl_util_image_tag() in resolve-kurl-util-image-tag.sh --
# the single source testgrid-pr.yaml and the release workflows use to decide
# which replicated/kurl-util tag a built installer references.
#
# Guards replicatedhq/kURL#6171 bug 2: testgrid-pr.yaml's label-triggered path
# (build-kurl-util-image=false) used to leave the templated installer
# referencing replicated/kurl-util:alpha while the installer/kurlnet manifest
# tag it actually renders is pinned to the per-version RC tag -- an image that
# was never built or pushed. The installer must always reference the
# per-version tag; what varies is only whether that tag's image is freshly
# built (build-kurl-util-image=true) or produced by retagging+pushing the
# already-built :alpha image (build-kurl-util-image=false, the cheap default).

# shellcheck source=resolve-kurl-util-image-tag.sh
. ./bin/resolve-kurl-util-image-tag.sh

testResolvesToVersionTagWhenBuildingFreshImage() {
    local result
    result="$(resolve_kurl_util_image_tag "true" "v2026.10.01-0-rc-pr6171-a25c664")"
    assertEquals "replicated/kurl-util:v2026.10.01-0-rc-pr6171-a25c664" "${result}"
}

testResolvesToVersionTagWhenReusingAlphaImage() {
    # This is the regression case: previously returned "replicated/kurl-util:alpha"
    # here, which does not match the tag the generated installer/kurlnet
    # manifests actually reference, so the kurlnet pods ErrImagePull.
    local result
    result="$(resolve_kurl_util_image_tag "false" "v2026.10.01-0-rc-pr6171-a25c664")"
    assertEquals "replicated/kurl-util:v2026.10.01-0-rc-pr6171-a25c664" "${result}"
}

testRequiresVersionTag() {
    ( resolve_kurl_util_image_tag "false" "" ) >/dev/null 2>&1
    assertNotEquals "0" "$?"
}

# shellcheck source=/dev/null
. shunit2
