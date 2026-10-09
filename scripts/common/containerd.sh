# containerd_patch_for_minor_version returns the maximum patch version for the given minor version. uses
# $CONTAINERD_STEP_VERSIONS to determine the max patch. if the minor version is not found, returns an
# empty string.
function containerd_patch_for_minor_version() {
    local for_major=$1
    local for_minor=$2
    for i in "${CONTAINERD_STEP_VERSIONS[@]}"; do
        semverParse "$i"
        if [ "$major" == "$for_major" ] && [ "$minor" == "$for_minor" ]; then
            echo "$patch"
            return 0
        fi
    done
    echo ""
}

# containerd_migration_steps returns an array with all steps necessary to migrate from the current containerd
# version to the desired version.
function containerd_migration_steps() {
    local from_version=$1
    local to_version=$2

    local current_minor
    local current_major
    semverParse "$from_version"
    current_major="$major"
    current_minor=$((minor + 1))

    local install_minor
    semverParse "$to_version"
    install_minor="$minor"
    install_major="$major"

    local steps=()
    while [ "$current_minor" -lt "$install_minor" ]; do
        max_patch=$(containerd_patch_for_minor_version "$current_major" "$current_minor")
        if [ -z "$max_patch" ]; then
            bail "error: could not find patch for containerd minor version v$current_major.$current_minor"
        fi
        steps+=("$install_major.$current_minor.$max_patch")
        current_minor=$((current_minor + 1))
    done
    steps+=("$to_version")

    echo "${steps[@]}"
}

# containerd_upgrade_between_majors returns true if the upgrade is between major versions.
function containerd_upgrade_between_majors() {
    local from_version=$1
    local to_version=$2

    local from_major
    semverParse "$from_version"
    from_major="$major"

    local to_major
    semverParse "$to_version"
    to_major="$major"

    test "$from_major" -ne "$to_major"
}

# containerd_upgrade_is_possible verifies if an upgrade between the provided containerd
# versions is possible. we verify if the installed containerd is known to us, if there
# is no major versions upgrades and if the minor version upgrade is not too big.
function containerd_upgrade_is_possible() {
    local from_version=$1
    local to_version=$2

    if containerd_upgrade_between_majors "$from_version" "$to_version" ; then
        # semverParse sets bare globals $major/$minor/$patch — capture IMMEDIATELY before any
        # subsequent semverParse or semverCompare call overwrites them.
        semverParse "$from_version"
        local from_major_local="$major"
        local from_minor_local="$minor"
        semverParse "$to_version"
        local to_major_local="$major"
        # $major/$minor now reflect to_version — from_major_local/from_minor_local are safe.

        # Only allow 1.7 -> 2.x; earlier 1.x minors must step through 1.7 first.
        if [ "$from_major_local" -ne "1" ] || [ "$from_minor_local" -ne "7" ] || [ "$to_major_local" -ne "2" ]; then
            bail "Upgrade from containerd v$from_version to v$to_version is not supported. Upgrade to containerd 1.7.x first."
        fi

        # Guard: containerd 2.x requires CRI v1; Kubernetes < 1.26 requires CRI v1alpha2.
        if [ -n "$CURRENT_KUBERNETES_VERSION" ]; then
            local k8s_minor
            k8s_minor="$(kubernetes_version_minor "$CURRENT_KUBERNETES_VERSION")"
            if [ "$k8s_minor" -lt "26" ]; then
                bail "containerd 2.x requires CRI v1, but Kubernetes $CURRENT_KUBERNETES_VERSION uses CRI v1alpha2. Upgrade Kubernetes to 1.26+ before upgrading containerd to 2.x."
            fi
        fi

        # Cross-major upgrade is valid (1.7 -> 2.x); skip the same-major minor-span check below.
        # Note: a 2.x -> 1.x downgrade attempt is caught above because from_major_local=2 ≠ 1,
        # which triggers the bail with "not supported". The semverCompare downgrade check below
        # is not reached for cross-major paths, but the cross-major guard already handles it.
        return 0
    fi

    semverCompare "$from_version" "$to_version"
    if [ "$SEMVER_COMPARE_RESULT"  = "1" ]; then
        bail "Downgrading containerd (from v$from_version to v$to_version) is not supported."
    fi

    semverParse "$from_version"
    local current_minor
    current_minor="$minor"

    semverParse "$to_version"
    local installing_minor
    installing_minor="$minor"

    if [ "$installing_minor" -gt "$((current_minor + 2))" ]; then
        logFail "Cannot upgrade containerd from v$from_version to v$to_version"
        logFail "This installer supports only containerd upgrades spanning two minor versions."
        bail "Please consider upgrading to an older containerd version first."
    fi
}

# containerd_verify_kubernetes_1_37_compatibility bails if the containerd version being
# installed is older than 2.x while Kubernetes is targeting kubeadm.k8s.io/v1beta4
# (Kubernetes 1.37+). This mirrors the CRI v1 guard in containerd_upgrade_is_possible
# above, but fires on every install/join (not just a containerd version upgrade):
# Kubernetes 1.37+ dropped upstream support for containerd 1.x, so containerd must
# already be 2.x by the time Kubernetes 1.37+ is installed.
function containerd_verify_kubernetes_1_37_compatibility() {
    local containerd_version="$1"
    local containerd_major="${containerd_version%%.*}"

    if [ "$(kubeadm_conf_api_version)" = "v1beta4" ] && [ "$containerd_major" -lt "2" ]; then
        bail "Kubernetes 1.37+ requires containerd 2.x, but containerd $containerd_version was selected. Upgrade containerd to 2.x before installing or upgrading to Kubernetes 1.37+."
    fi
}

# containerd_evaluate_upgrade verifies if containerd upgrade between the two provided versions
# is possible and in case it is, returns the list of steps necessary to perform the upgrade.
# each step is a version of containerd that we need to install.
export CONTAINERD_INSTALL_VERSIONS=()
function containerd_evaluate_upgrade() {
    local from_version=$1
    local to_version=$2
    if use_os_containerd ; then
        return 0
    fi
    echo "Evaluating if an upgrade from containerd v$from_version to v$to_version is possible."
    containerd_upgrade_is_possible "$from_version" "$to_version"
    echo "Containerd upgrade from v$from_version to v$to_version is possible."
    for version in $(containerd_migration_steps "$from_version" "$to_version"); do
        CONTAINERD_INSTALL_VERSIONS+=("$version")
    done
}

function use_os_containerd() {
    if ! host_packages_shipped && ! is_rhel_9_variant ; then
        # we ship containerd packages for RHEL9, but not for the later no-shipped-packages distros
        return 0
    fi
    return 1
}
