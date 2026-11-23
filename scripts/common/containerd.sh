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
# above, but fires on every install/join (not just a containerd version upgrade).
# Upstream Kubernetes support for containerd 1.x ends at 1.35, but kURL shipped
# Kubernetes 1.36 with containerd 1.x, so containerd 2.x is only required from 1.37.
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

# containerd_find_pause_image_lines lists containerd's imported images and prints (on stdout)
# the `ctr images list` line(s) matching the given sandbox_image ref, falling back to matching
# by repo+tag or by digest when sandbox_image records a ref that containerd imported the image
# under a different name for (an airgap mirror rewrite, or sandbox_image itself pinned to a
# digest while the image was imported by tag). An exact ref match prints that one line. A digest
# match prints every ref sharing the digest: the pinned label is per-ref, and an alias or mirror
# ref may be the one containerd resolves for the sandbox, so callers pin all of them. Prints
# nothing -- not an error -- when the image is simply not imported. Returns non-zero (already
# logWarn'd) when the list itself failed or the repo+tag fallback matched more than one image
# ambiguously; callers must stop in that case.
function containerd_find_pause_image_lines() {
    local sock="$1" pause_image="$2"

    local list_output=
    if ! list_output="$(ctr -a "$sock" -n=k8s.io images list 2>&1)"; then
        logWarn "Failed to list containerd images while checking pause-image pin ($list_output); will retry on next install/upgrade run"
        return 1
    fi

    local image_lines=
    image_lines="$(echo "$list_output" | awk -v img="$pause_image" '$1 == img { print; exit }')"
    if [ -z "$image_lines" ]; then
        case "$pause_image" in
            *@sha256:*)
                local pause_digest="${pause_image##*@}"
                image_lines="$(echo "$list_output" | awk -v d="$pause_digest" '$3 == d { print }')"
                ;;
            *)
                local pause_repo_tag="${pause_image##*/}"
                local repo_tag_matches
                repo_tag_matches="$(echo "$list_output" | awk -v rt="$pause_repo_tag" '
                    $1 == rt { print; next }
                    {
                        suffix = "/" rt
                        n = length($1) - length(suffix)
                        if (n >= 0 && substr($1, n + 1) == suffix) print
                    }
                ')"
                if [ -n "$repo_tag_matches" ] && [ "$(echo "$repo_tag_matches" | wc -l)" -gt 1 ]; then
                    logWarn "Multiple containerd images match pause image repo+tag $pause_repo_tag ambiguously; skipping pin, will retry on next install/upgrade run"
                    return 1
                fi
                image_lines="$repo_tag_matches"
                ;;
        esac
    fi

    echo "$image_lines"
}

# containerd_wait_active_for_pause_pin prints containerd's `systemctl is-active` state once it
# settles. activating/deactivating are transient right after install_cri restarts containerd,
# so they are retried briefly instead of silently skipping the pin. Returns 0 only when
# containerd is active; any other final state returns non-zero (warning only when the state
# itself is unexpected -- inactive/failed/unknown are legitimate reasons to skip).
function containerd_wait_active_for_pause_pin() {
    local active_status=
    local attempt=0
    local max_attempts="${CONTAINERD_PAUSE_PIN_ACTIVE_RETRIES:-10}"
    while true; do
        if active_status="$(systemctl is-active containerd 2>&1)"; then
            return 0
        fi
        case "$active_status" in
            activating|deactivating)
                attempt=$((attempt + 1))
                if [ "$attempt" -ge "$max_attempts" ]; then
                    logWarn "containerd is still $active_status after $attempt checks; skipping pause-image pin check, will retry on next install/upgrade run"
                    return 1
                fi
                sleep "${CONTAINERD_PAUSE_PIN_RETRY_SLEEP:-1}"
                ;;
            inactive|failed|unknown)
                return 1
                ;;
            *)
                logWarn "systemctl is-active containerd returned an unexpected result ($active_status); skipping pause-image pin check, will retry on next install/upgrade run"
                return 1
                ;;
        esac
    done
}

# containerd_ensure_pause_image_pinned guards against a containerd 1.x gap: it only marks an
# image io.cri-containerd.pinned=pinned the first time it observes an image matching the
# running process's sandbox_image (pkg/cri/server/image_pull.go). A kURL upgrade imports the
# new pause image into containerd while the OLD daemon (with the OLD sandbox_image) is still
# running, then restarts containerd with the new sandbox_image already written to config.toml
# -- so the new pause image is never pinned. Kubelet GC (Kubernetes >= 1.29) or
# `crictl rmi --prune` can then remove it; on an airgapped host that cannot re-pull it, the next
# reboot takes the control plane down. containerd 2.x re-checks the pin on every image event and
# does not expose sandbox_image in config.toml at all, so kubernetes_containerd_pause_image
# already returns empty there and this is a no-op.
#
# It is called from the two places the pause image can land in containerd, so main() ordering
# in install.sh/join.sh/upgrade.sh does not matter:
#   - install_cri, right after the containerd add-on imports the new pause image and restarts
#     containerd (the exact gap above). This call heals: if kubeadm has already configured this
#     node (KUBELET_FLAGS_FILE exists) but the image is absent -- kubelet GC removed it while it
#     was unpinned, or the add-on's own import failed -- it imports the kubernetes package images
#     via kubernetes_load_images and retries. That makes every kURL run fix clusters that
#     upgraded before this fix existed.
#   - kubernetes_load_images, after it imports the package images (fresh install/join, and the
#     node upgrade in maybe_upgrade). Called with "no-heal" since it is itself the import step.
# Safe to call on every run: every failure warns and returns 0.
function containerd_ensure_pause_image_pinned() {
    local heal=1
    if [ "${1:-}" = "no-heal" ]; then
        heal=0
    fi

    if [ -z "$CONTAINERD_VERSION" ] || [ ! -f /etc/containerd/config.toml ]; then
        return 0
    fi

    containerd_wait_active_for_pause_pin || return 0

    local pause_image=
    pause_image="$(kubernetes_containerd_pause_image)"
    if [ -z "$pause_image" ]; then
        return 0
    fi

    local sock=
    if ! sock="$("${K8S_DISTRO}"_get_containerd_sock)"; then
        logWarn "Failed to resolve the containerd socket via ${K8S_DISTRO}_get_containerd_sock; skipping pause-image pin check, will retry on next install/upgrade run"
        return 0
    fi

    local image_lines=
    image_lines="$(containerd_find_pause_image_lines "$sock" "$pause_image")" || return 0

    if [ -z "$image_lines" ]; then
        if [ "$heal" != "1" ] || [ ! -f "$KUBELET_FLAGS_FILE" ]; then
            # Either the caller is the import step itself, or kubeadm has never configured this
            # node (a fresh install before images are loaded). Nothing to heal here; the
            # kubernetes_load_images call that imports the image will pin it.
            return 0
        fi

        logWarn "Pause image $pause_image is not in containerd; importing Kubernetes $KUBERNETES_VERSION package images so it can be pinned"
        local reimport_rc=0
        kubernetes_load_images "$KUBERNETES_VERSION" || reimport_rc=$?
        if [ "$reimport_rc" -ne 0 ]; then
            logWarn "Failed to import Kubernetes $KUBERNETES_VERSION package images while restoring pause image $pause_image (exit $reimport_rc); will retry on next install/upgrade run"
        fi
        image_lines="$(containerd_find_pause_image_lines "$sock" "$pause_image")" || return 0
        if [ -z "$image_lines" ]; then
            logWarn "Pause image $pause_image still missing from containerd after importing Kubernetes package images; will retry on next install/upgrade run"
            return 0
        fi
    fi

    local image_line=
    local matched_ref=
    local label_output=
    while IFS= read -r image_line; do
        if [ -z "$image_line" ] || echo "$image_line" | grep -q 'io.cri-containerd.pinned=pinned'; then
            continue
        fi

        matched_ref="$(echo "$image_line" | awk '{ print $1 }')"
        log "Pinning containerd pause image $matched_ref"
        if ! label_output="$(ctr -a "$sock" -n=k8s.io images label -- "$matched_ref" io.cri-containerd.pinned=pinned 2>&1 < /dev/null)"; then
            logWarn "Failed to pin containerd pause image $matched_ref ($label_output); will retry on next install/upgrade run"
        elif [ -n "$label_output" ]; then
            echo "$label_output"
        fi
    done <<< "$image_lines"
    return 0
}

function use_os_containerd() {
    if ! host_packages_shipped && ! is_rhel_9_variant ; then
        # we ship containerd packages for RHEL9, but not for the later no-shipped-packages distros
        return 0
    fi
    return 1
}
