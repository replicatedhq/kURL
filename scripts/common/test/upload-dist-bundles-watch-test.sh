#!/bin/bash

# Tests the change-detection match used in bin/upload-dist-staging.sh and
# bin/upload-dist-versioned.sh that decides whether a package key should also
# watch bundles/ for changes. Real kubernetes host packages (kubernetes-<version>)
# depend on bundles/; kubernetes-conformance-* archives do NOT and must not match.

# Mirrors the guard in the upload-dist scripts:
#   if echo "${key}" | grep -qE "kubernetes-[0-9]" ; then paths+=( "bundles/" ); fi
key_watches_bundles()
{
    echo "$1" | grep -qE "kubernetes-[0-9]"
}

testKubernetesPackageWatchesBundles()
{
    key_watches_bundles "kubernetes-1.35.7"
    assertEquals "kubernetes-1.35.7 should watch bundles/" "0" "$?"
}

testKubernetesConformanceDoesNotWatchBundles()
{
    key_watches_bundles "kubernetes-conformance-1.35.7"
    assertEquals "kubernetes-conformance-1.35.7 should NOT watch bundles/" "1" "$?"
}

testOtherKubernetesVersionsWatchBundles()
{
    key_watches_bundles "kubernetes-1.24.0"
    assertEquals "kubernetes-1.24.0 should watch bundles/" "0" "$?"

    key_watches_bundles "kubernetes-1.30.5"
    assertEquals "kubernetes-1.30.5 should watch bundles/" "0" "$?"
}

testNonKubernetesPackageDoesNotWatchBundles()
{
    key_watches_bundles "containerd-1.6.4"
    assertEquals "containerd-1.6.4 should NOT watch bundles/" "1" "$?"
}

. shunit2
