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

# containerd_latest_step_for_major prints the highest version in $CONTAINERD_STEP_VERSIONS for the
# given major version, or an empty string if there is none. the server builds the array with one
# entry per minor (unordered, majors mixed, 0.0.0 placeholders), so the whole array is scanned.
function containerd_latest_step_for_major() {
    local for_major=$1
    local latest=
    local i
    for i in "${CONTAINERD_STEP_VERSIONS[@]}"; do
        semverParse "$i"
        if [ "$major" != "$for_major" ]; then
            continue
        fi
        if [ -z "$latest" ]; then
            latest="$i"
            continue
        fi
        semverCompare "$latest" "$i"
        if [ "$SEMVER_COMPARE_RESULT" = "-1" ]; then
            latest="$i"
        fi
    done
    echo "$latest"
}

# containerd_migration_steps returns an array with all steps necessary to migrate from the current containerd
# version to the desired version. an upgrade from 1.x to 2.x first steps through the latest 1.x
# version (1.7, see containerd_upgrade_is_possible), then goes straight to the 2.x target.
function containerd_migration_steps() {
    local from_version=$1
    local to_version=$2

    # semverParse sets bare globals $major/$minor/$patch, capture them right away
    local from_major from_minor
    semverParse "$from_version"
    from_major="$major"
    from_minor="$minor"

    local install_major install_minor
    semverParse "$to_version"
    install_major="$major"
    install_minor="$minor"

    local steps=()

    if [ "$from_major" -lt "$install_major" ]; then
        local bridge_version bridge_minor
        bridge_version="$(containerd_latest_step_for_major "$from_major")"
        semverParse "$bridge_version"
        bridge_minor="$minor"
        if [ -n "$bridge_version" ] && [ "$from_minor" -lt "$bridge_minor" ]; then
            # shellcheck disable=SC2207
            steps+=($(containerd_migration_steps "$from_version" "$bridge_version"))
        fi
        steps+=("$to_version")
        echo "${steps[@]}"
        return 0
    fi

    local current_minor=$((from_minor + 1))
    local max_patch
    while [ "$current_minor" -lt "$install_minor" ]; do
        max_patch=$(containerd_patch_for_minor_version "$from_major" "$current_minor")
        if [ -z "$max_patch" ]; then
            bail "error: could not find patch for containerd minor version v$from_major.$current_minor"
        fi
        steps+=("$from_major.$current_minor.$max_patch")
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
# versions is possible. we verify if the installed containerd is known to us, that a major
# version upgrade goes from 1.x to 2.x and that the minor version upgrade is not too big.
# containerd supports 2.x upgrades only from 1.7, so older 1.x versions step through the latest
# 1.7 version first (see containerd_migration_steps). all checks live here, not in
# containerd_migration_steps, because that one runs in a subshell where bail cannot stop the install.
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

        if [ "$from_major_local" -gt "$to_major_local" ]; then
            bail "Downgrading containerd (from v$from_version to v$to_version) is not supported."
        fi

        if [ "$from_major_local" -ne "1" ] || [ "$to_major_local" -ne "2" ]; then
            bail "Upgrade from containerd v$from_version to v$to_version is not supported."
        fi

        # Guard: containerd 2.x requires CRI v1; Kubernetes < 1.26 requires CRI v1alpha2.
        # Checked before the 1.x steps so nothing is installed when it fails.
        if [ -n "$CURRENT_KUBERNETES_VERSION" ]; then
            local k8s_minor
            k8s_minor="$(kubernetes_version_minor "$CURRENT_KUBERNETES_VERSION")"
            if [ "$k8s_minor" -lt "26" ]; then
                bail "containerd 2.x requires CRI v1, but Kubernetes $CURRENT_KUBERNETES_VERSION uses CRI v1alpha2. Upgrade Kubernetes to 1.26+ before upgrading containerd to 2.x."
            fi
        fi

        # 1.x versions older than 1.7 step through the latest 1.7 version first.
        local bridge_version bridge_minor
        bridge_version="$(containerd_latest_step_for_major "1")"
        semverParse "$bridge_version"
        bridge_minor="$minor"
        if [ -z "$bridge_version" ] || [ "$bridge_minor" != "7" ]; then
            bail "Upgrade from containerd v$from_version to v$to_version is not supported. Upgrade to containerd 1.7.x first."
        fi

        if [ "$from_minor_local" -lt "$bridge_minor" ]; then
            log "Upgrading containerd from v$from_version to v$to_version steps through containerd v$bridge_version first."
            # the 1.x leg follows the rules of any 1.x upgrade: no downgrade, at most two minors
            containerd_upgrade_is_possible "$from_version" "$bridge_version"
        fi

        # 1.7 -> 2.x goes straight to the 2.x target; the same-major minor-span check below
        # does not apply across majors.
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
# above, but fires on every install/join (not just a containerd version upgrade).
# Upstream Kubernetes support for containerd 1.x ends at 1.35. kURL shipped Kubernetes
# 1.36 with containerd 1.x, so existing 1.36 clusters keep running on it, but new 1.36
# installs and upgrades into 1.36 need containerd 2.x too. That is checked by
# containerd_bail_if_kubernetes_1_36_unsupported below, from install.sh only.
function containerd_verify_kubernetes_1_37_compatibility() {
    local containerd_version="$1"
    local containerd_major="${containerd_version%%.*}"

    if [ "$(kubeadm_conf_api_version)" = "v1beta4" ] && [ "$containerd_major" -lt "2" ]; then
        bail "Kubernetes 1.37+ requires containerd 2.x, but containerd $containerd_version was selected. Upgrade containerd to 2.x before installing or upgrading to Kubernetes 1.37+."
    fi
}

# containerd_bail_if_kubernetes_1_36_unsupported bails when install.sh would create a
# Kubernetes 1.36 cluster, or upgrade one into 1.36, with containerd 1.x. Clusters where
# every node already runs 1.36 are left alone so they keep working. Nodes that use the
# OS-provided containerd run the OS package whatever version the spec selects, so the
# installed OS containerd is checked instead. install.sh calls this again after
# install_cri, once that package is installed.
function containerd_bail_if_kubernetes_1_36_unsupported() {
    local containerd_version="$1"

    if [ "$(kubernetes_version_minor "$KUBERNETES_VERSION")" != "36" ]; then
        return 0
    fi

    # lowest Kubernetes version across the cluster's nodes, empty on a new cluster
    local min_version
    min_version="$(kubernetes_upgrade_discover_min_kubernetes_version)"
    if [ -n "$min_version" ] && [ "$(kubernetes_version_minor "$min_version")" -ge "36" ]; then
        return 0
    fi

    if use_os_containerd; then
        local os_containerd_version
        os_containerd_version="$(containerd_installed_version)"
        if [ -n "$os_containerd_version" ] && [ "${os_containerd_version%%.*}" -lt "2" ]; then
            bail "Kubernetes 1.36 requires containerd 2.x, but this node uses the containerd $os_containerd_version provided by the Operating System. Upgrade the OS containerd package to 2.x, then run the installer again."
        fi
        return 0
    fi

    if [ "${containerd_version%%.*}" -lt "2" ]; then
        local next_step="Select containerd 2.x to install or upgrade to Kubernetes 1.36."
        if [ -n "$min_version" ] && [ "$(kubernetes_version_minor "$min_version")" -lt "26" ]; then
            # containerd 2.x needs CRI v1, which Kubernetes 1.26 is the first to require
            next_step="Upgrade to containerd 1.7.x and Kubernetes 1.26 or later first, then select containerd 2.x together with Kubernetes 1.36."
        fi
        bail "Kubernetes 1.36 requires containerd 2.x, but containerd $containerd_version was selected. $next_step"
    fi
}

# containerd_installed_version prints the version of /usr/bin/containerd, or nothing if it is not installed.
function containerd_installed_version() {
    if [ -x /usr/bin/containerd ]; then
        /usr/bin/containerd --version | cut -d " " -f3 | tr -d 'v'
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

    # some add-ons install an older containerd on some OSes (the 2.x add-ons install 1.6.33 on
    # rhel-7), so check the upgrade against the version the add-on really installs here.
    local delivered_version
    delivered_version="$(containerd_addon_delivered_version "$to_version")"

    echo "Evaluating if an upgrade from containerd v$from_version to v$delivered_version is possible."
    containerd_upgrade_is_possible "$from_version" "$delivered_version"
    echo "Containerd upgrade from v$from_version to v$delivered_version is possible."

    # steps are add-on versions: intermediate steps come from $CONTAINERD_STEP_VERSIONS (such as
    # the 1.7 step of a 1.x to 2.x upgrade), and the last one must be the selected add-on, not the
    # containerd version it delivers. when the add-on delivers the installed 1.x version (2.x
    # add-ons on rhel-7), there is no cross-major upgrade and so no 1.7 step.
    for version in $(containerd_migration_steps "$from_version" "$delivered_version"); do
        if [ "$version" = "$delivered_version" ]; then
            version="$to_version"
        fi
        CONTAINERD_INSTALL_VERSIONS+=("$version")
    done
}

# containerd_addon_delivered_version prints the containerd version the given add-on installs on
# this host, read from its Manifest "dockerout <dir> <dockerfile> <version>" line, or the add-on
# version when there is no such line.
function containerd_addon_delivered_version() {
    local addon_version="$1"
    local manifest="$DIR/addons/containerd/$addon_version/Manifest"

    local package_dir
    case "$LSB_DIST" in
        ubuntu) package_dir="ubuntu-$DIST_VERSION" ;;
        amzn) package_dir="rhel-7" ;;
        *) package_dir="rhel-$DIST_VERSION_MAJOR" ;;
    esac

    local delivered_version=
    if [ -f "$manifest" ]; then
        delivered_version="$(awk -v dir="$package_dir" '$1 == "dockerout" && $2 == dir { print $4; exit }' "$manifest")"
    fi
    echo "${delivered_version:-$addon_version}"
}

# containerd_ensure_pause_image_pinned labels the sandbox (pause) image
# io.cri-containerd.pinned=pinned so kubelet GC and `crictl rmi --prune` cannot delete it.
# containerd 1.x only pins an image the first time it sees one matching the running daemon's
# sandbox_image, but a kURL upgrade imports the new pause image while the old daemon (with the
# old sandbox_image) is still running, so it is never pinned (sc-140018). On an airgapped host
# that cannot re-pull it, the next reboot takes the control plane down. containerd 2.x has no
# sandbox_image in config.toml, so this is a no-op there. Every failure warns and returns 0.
function containerd_ensure_pause_image_pinned() {
    if [ -z "$CONTAINERD_VERSION" ] || [ ! -f /etc/containerd/config.toml ]; then
        return 0
    fi
    if ! systemctl is-active --quiet containerd; then
        return 0
    fi

    local pause_image=
    pause_image="$(kubernetes_containerd_pause_image)"
    if [ -z "$pause_image" ]; then
        return 0
    fi

    local sock=
    if ! sock="$("${K8S_DISTRO}"_get_containerd_sock)"; then
        logWarn "Failed to resolve the containerd socket; skipping pause image pin"
        return 0
    fi

    local list_output=
    if ! list_output="$(ctr -a "$sock" -n=k8s.io images list 2>&1)"; then
        logWarn "Failed to list containerd images to pin pause image $pause_image ($list_output)"
        return 0
    fi

    local image_line=
    image_line="$(echo "$list_output" | awk -v img="$pause_image" '$1 == img { print; exit }')"
    if [ -z "$image_line" ] || echo "$image_line" | grep -q 'io.cri-containerd.pinned=pinned'; then
        return 0
    fi

    log "Pinning containerd pause image $pause_image"
    local label_output=
    if ! label_output="$(ctr -a "$sock" -n=k8s.io images label -- "$pause_image" io.cri-containerd.pinned=pinned 2>&1)"; then
        logWarn "Failed to pin containerd pause image $pause_image ($label_output)"
    elif [ -n "$label_output" ]; then
        echo "$label_output"
    fi
    return 0
}

# containerd_install_upgrade_steps installs each version in $CONTAINERD_INSTALL_VERSIONS in order.
# online, intermediate versions are downloaded one at a time. airgap, the bundle ships the
# target and the previous minor only, so intermediate versions missing locally (such as the 1.7
# step of a 1.x to 2.x upgrade) are requested up front, before any containerd is touched, the
# same way Kubernetes upgrade steps are. the add-on scripts read $CONTAINERD_VERSION, so it is set
# to the step version while that step installs.
function containerd_install_upgrade_steps() {
    local target_version="$CONTAINERD_VERSION"
    local version

    if [ "$AIRGAP" = "1" ]; then
        local missing=()
        for version in "${CONTAINERD_INSTALL_VERSIONS[@]}"; do
            if [ "$version" != "$target_version" ] && [ ! -f "$DIR/addons/containerd/$version/install.sh" ]; then
                missing+=("containerd-$version")
            fi
        done
        if [ "${#missing[@]}" -gt 0 ]; then
            addon_fetch_multiple_airgap "${missing[@]}"
        fi
    fi

    for version in "${CONTAINERD_INSTALL_VERSIONS[@]}"; do
        logStep "Moving containerd to version v$version."
        if [ "$version" != "$target_version" ] && [ "$AIRGAP" != "1" ] ; then
            log "Downloading containerd v$version."
            addon_fetch "containerd" "$version"
        fi
        CONTAINERD_VERSION="$version"
        addon_install "containerd" "$version"
    done
    CONTAINERD_VERSION="$target_version"
}

function use_os_containerd() {
    if ! host_packages_shipped && ! is_rhel_9_variant ; then
        # we ship containerd packages for RHEL9, but not for the later no-shipped-packages distros
        return 0
    fi
    return 1
}
