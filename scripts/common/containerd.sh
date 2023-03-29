# containerd_patch_for_minor_version returns the maximum patch version for the given minor version. uses
# $CONTAINERD_STEP_VERSIONS to determine the max patch. if the minor version is not found, returns 0.
function containerd_patch_for_minor_version() {
    local for_minor=$1
    for i in "${CONTAINERD_STEP_VERSIONS[@]}"; do
        semverParse "$i"
        if [ "$minor" == "$for_minor" ]; then
            echo "$patch"
            return 0
        fi
    done
    echo "0"
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
        max_patch=$(containerd_patch_for_minor_version "$current_minor")
        if [ "$max_patch" = "0" ]; then
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

    # so far we don't have containerd version 2 and when it comes we don't know exactly
    # from what version we will be able to upgrade to it from. so, for now, we block
    # the attempt so when the version arrives the testgrid will fail.
    if containerd_upgrade_between_majors "$from_version" "$to_version" ; then
        bail "Upgrade between containerd major versions is not supported by this installer."
    fi

    semverParse "$from_version"
    local current_minor
    current_minor="$minor"

    semverParse "$to_version"
    local installing_minor
    installing_minor="$minor"

    if [ "$installing_minor" -lt "$current_minor" ]; then
        bail "Downgrading containerd (from v$from_version to v$to_version) is not supported."
    fi

    if [ "$installing_minor" -gt "$((current_minor + 2))" ]; then
        logFail "Cannot upgrade containerd from v$from_version to v$to_version"
        logFail "This installer supports only containerd upgrades spanning two minor versions."
        bail "Please consider upgrading to an older containerd version first."
    fi
}

# containerd_evaluate_upgrade verifies if containerd upgrade between the two provided versions
# is possible and in case it is, returns the list of steps necessary to perform the upgrade.
# each step is a version of containerd that we need to install.
export CONTAINERD_INSTALL_VERSIONS=()
function containerd_evaluate_upgrade() {
    local from_version=$1
    local to_version=$2
    echo "Evaluating if an upgrade from containerd v$from_version to v$to_version is possible."
    containerd_upgrade_is_possible "$from_version" "$to_version"
    echo "Containerd upgrade from v$from_version to v$to_version is possible."
    for version in $(containerd_migration_steps "$from_version" "$to_version"); do
        CONTAINERD_INSTALL_VERSIONS+=("$version")
    done
}
