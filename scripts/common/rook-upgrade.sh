# shellcheck disable=SC2148

export PV_BASE_PATH=/opt/replicated/rook

# rook_upgrade_maybe_report_upgrade_rook checks if rook should be upgraded before upgrading k8s,
# prompts the user to confirm the upgrade, and starts the upgrade process.
function rook_upgrade_maybe_report_upgrade_rook() {
    local current_version=
    current_version="$(current_rook_version)"
    local desired_version="$ROOK_VERSION"

    if ! rook_upgrade_should_upgrade_rook "$current_version" "$desired_version" ; then
        return
    fi

    if ! rook_upgrade_prompt "$current_version" "$desired_version" ; then
        bail "Not upgrading Rook"
    fi
    rook_upgrade_report_upgrade_rook "$current_version" "$desired_version"

    # shellcheck disable=SC1090
    addon_source "rook" "$ROOK_VERSION" # This will undo the override from above prior to running addon_install
}

# rook_upgrade_should_upgrade_rook checks the currently installed rook version and the desired rook
# version. If the current version is two minor versions or more less than the desired version, then
# the function will return true.
function rook_upgrade_should_upgrade_rook() {
    local current_version="$1"
    local desired_version="$2"

    # rook is not installed, so no upgrade
    if [ -z "$current_version" ]; then
        return 1
    fi
    # rook is not requested to be installed, so no upgrade
    if [ -z "$desired_version" ]; then
        return 1
    fi

    semverParse "$current_version"
    # shellcheck disable=SC2154
    local current_rook_version_major="$major"
    # shellcheck disable=SC2154
    local current_rook_version_minor="$minor"

    semverParse "$desired_version"
    local next_rook_version_major="$major"
    local next_rook_version_minor="$minor"
    # shellcheck disable=SC2154
    local next_rook_version_patch="$patch"

    # upgrades not supported for major versions not equal to 1
    if [ "$current_rook_version_major" != "1" ] || [ "$next_rook_version_major" != "1" ]; then
        return 1
    fi

    # upgrade not needed for minor versions equal
    if [ "$current_rook_version_minor" = "$next_rook_version_minor" ]; then
        return 1
    fi

    # upgrades not supported to minor versions less than 4
    if [ "$next_rook_version_minor" -lt "4" ]; then
        return 1
    # special case 1.0 to 1.4 upgrade
    elif [ "$next_rook_version_minor" = "4" ]; then
        # upgrades not supported from to 1.4 patch versions less than 1.4.9
        if [ "$next_rook_version_patch" -lt "9" ]; then
            return 1
        fi
        return 0
    fi

    # current version must be greater than or equal to desired version - 1 since the add-on itself
    # can do single version upgrades although this is not true for minor versions less than 4
    if [ "$current_rook_version_minor" -ge "$((next_rook_version_minor - 1))" ]; then
        return 1
    fi

    return 0
}

# rook_upgrade_prompt prompts the user to confirm the rook upgrade.
function rook_upgrade_prompt() {
    local current_version="$1"
    local desired_version="$2"
    logWarn "$(printf "This script will upgrade Rook from %s to %s." "$current_version" "$desired_version")"
    logWarn "Upgrading Rook will take some time and will place additional load on your server."
    if ! "$DIR"/bin/kurl rook has-sufficient-blockdevices ; then
        logWarn "In order to complete this migration, you may need to attach a blank disk to each node in the cluster for Rook to use."
    fi
    printf "Would you like to continue? "

    confirmN
}

# rook_upgrade_report_upgrade_rook reports the upgrade and starts the upgrade process.
function rook_upgrade_report_upgrade_rook() {
    local current_version="$1"
    local desired_version="$2"

    local from_version=
    from_version="$(rook_upgrade_rook_version_to_major_minor "$current_version")"

    local to_version=
    to_version="$(rook_upgrade_rook_version_to_major_minor "$desired_version")"

    ROOK_UPGRADE_VERSION="v2.0.0" # if you change this code, change the version
    report_addon_start "rook_${from_version}_to_${to_version}" "$ROOK_UPGRADE_VERSION"
    export REPORTING_CONTEXT_INFO="rook_${from_version}_to_${to_version} $ROOK_UPGRADE_VERSION"
    rook_upgrade "$from_version" "$to_version"
    export REPORTING_CONTEXT_INFO=""
    report_addon_success "rook_${from_version}_to_${to_version}" "$ROOK_UPGRADE_VERSION"
}

# rook_upgrade upgrades will fetch the add-on and load the images for the upgrade and finally run
# the upgrade script.
function rook_upgrade() {
    local from_version="$1"
    local to_version="$2"

    rook_disable_ekco_operator

    logStep "Upgrading Rook from $from_version.x to $to_version.x"
    rook_upgrade_print_list_of_minor_upgrades "$from_version" "$to_version"
    echo "This may take some time."
    if ! rook_upgrade_addon_fetch_and_load "$from_version" "$to_version" ; then
        logFail "Cancelling Rook $from_version.x to $to_version.x upgrade"
        return 1
    fi

    rook_upgrade_prompt_missing_images "$from_version" "$to_version"

    # delete the mutatingwebhookconfiguration and remove the rook-priority.kurl.sh label
    # as the EKCO rook-priority.kurl.sh mutating webhook is no longer necessary passed Rook
    # 1.0.4.
    kubectl label namespace rook-ceph rook-priority.kurl.sh-
    kubectl delete mutatingwebhookconfigurations rook-priority.kurl.sh --ignore-not-found

    if rook_upgrade_is_version_included "$from_version" "$to_version" "1.4" ; then
        addon_source "rookupgrade" "10to14"
        rookupgrade_10to14_upgrade "$from_version"
    fi

    # if to_version is greater than 1.4, then continue with the upgrade
    if [ "$(rook_upgrade_compare_rook_versions "$to_version" "1.4")" = "1" ]; then
        rook_upgrade_do_rook_upgrade "$(rook_upgrade_max_rook_version "1.4" "$from_version")" "$to_version"
    fi

    rook_enable_ekco_operator

    logSuccess "Successfully upgraded Rook from $from_version.x to $to_version.x"
}

# rook_upgrade_do_rook_upgrade will step through each minor version upgrade from $from_version to
# $to_version
function rook_upgrade_do_rook_upgrade() {
    local from_version="$1"
    local to_version="$2"

    local step=
    while read -r step; do
        if [ -z "$step" ]; then
            continue
        fi
        if ! addon_exists "rook" "$step" ; then
            logFail "Rook version $step not found"
            return 1
        fi
        logStep "Upgrading to Rook $step"
        # temporarily set the ROOK_VERSION since the add-on script relies on it
        local old_rook_version="$ROOK_VERSION"
        export ROOK_VERSION="$step"
        # shellcheck disable=SC1090
        addon_source "rook" "$step" # this will override the rook $ROOK_VERSION add-on functions
        if commandExists "rook_should_fail_install" ; then
            # NOTE: there is no way to know this is the correct rook version function
            if rook_should_fail_install ; then
                logFail "Rook $to_version will not be installed due to failed preflight checks"
                return 1
            fi
        fi
        # NOTE: there is no way to know this is the correct rook version function
        rook # upgrade to the step version
        ROOK_VERSION="$old_rook_version"
        logSuccess "Upgraded to Rook $step successfully"
    done <<< "$(rook_upgrade_step_versions "ROOK_STEP_VERSIONS[@]" "$from_version" "$to_version")"
}

# rook_upgrade_addon_fetch_and_load will fetch all add-on versions from $from_version to
# $to_version.
function rook_upgrade_addon_fetch_and_load() {
    local from_version="$1"
    local to_version="$2"

    logStep "Downloading images required for Rook $from_version to $to_version upgrade"

    if rook_upgrade_is_version_included "$from_version" "$to_version" "1.4" ; then
        if ! rook_upgrade_addon_fetch_and_load_step "rookupgrade" "10to14" ; then
            return 1
        fi
    fi

    if [ "$(rook_upgrade_compare_rook_versions "$to_version" "1.4")" = "1" ]; then
        local step=
        while read -r step; do
            if [ -z "$step" ] || [ "$step" = "0.0.0" ]; then
                continue
            fi
            if ! rook_upgrade_addon_fetch_and_load_step "rook" "$step" ; then
                return 1
            fi
        done <<< "$(rook_upgrade_step_versions "ROOK_STEP_VERSIONS[@]" "$(rook_upgrade_max_rook_version "1.4" "$from_version")" "$to_version")"
    fi

    logSuccess "Images loaded for Rook $from_version to $to_version upgrade"
}

# rook_upgrade_addon_fetch_and_load_step will fetch an individual add-on version.
function rook_upgrade_addon_fetch_and_load_step() {
    local addon="$1"
    local version="$2"

    if [ "$AIRGAP" = "1" ]; then
        if ! addon_fetch_airgap "$addon" "$version" ; then
            return 1
        fi
    else
        if ! addon_fetch "$addon" "$version" ; then
            return 1
        fi
    fi

    if ! addon_load "$addon" "$version" ; then
        return 1
    fi
}

# rook_upgrade_prompt_missing_images prompts the user to run the command to load the images on all
# remote nodes before proceeding.
function rook_upgrade_prompt_missing_images() {
    local from_version="$1"
    local to_version="$2"

    local images_list=

    if rook_upgrade_is_version_included "$from_version" "$to_version" "1.4" ; then
        images_list="$(rook_upgrade_list_rook_ceph_images_in_manifest_file "addons/rookupgrade/10to14/Manifest")"
    fi

    if [ "$(rook_upgrade_compare_rook_versions "$to_version" "1.4")" = "1" ]; then
        local step=
        while read -r step; do
            if [ -z "$step" ]; then
                continue
            fi
            images_list="$(rook_upgrade_merge_images_list \
                "$images_list" \
                "$(rook_upgrade_list_rook_ceph_images_in_manifest_file "addons/rook/$step/Manifest")" \
            )"
        done <<< "$(rook_upgrade_step_versions "ROOK_STEP_VERSIONS[@]" "$(rook_upgrade_max_rook_version "1.4" "$from_version")" "$to_version")"
    fi

    if [ -z "$images_list" ]; then
        return
    fi

    local this_hostname=
    this_hostname=$(hostname)

    local node_missing_images=
    # shellcheck disable=SC2086
    node_missing_images=$("$DIR"/bin/kurl cluster nodes-missing-images --image="$KURL_UTIL_IMAGE" --exclude-host="$this_hostname" $images_list)
    if [ -z "$node_missing_images" ]; then
        return
    fi

    local prefix=
    if [ "$AIRGAP" = "1" ]; then
        prefix="cat ./"
    else
        prefix="$(build_installer_prefix "$INSTALLER_ID" "$KURL_VERSION" "$KURL_URL" "$PROXY_ADDRESS")"
    fi

    local airgap_flag=
    if [ "$AIRGAP" = "1" ]; then
        airgap_flag="airgap"
    fi

    printf "The nodes %s appear to be missing images required for the Rook %s to %s migration.\n" "$node_missing_images" "$from_version" "$to_version"
    printf "Please run the following on each of these nodes before continuing:\n"
    printf "\n\t%b%stasks.sh | sudo bash -s rook-upgrade-load-images from-version=%s to-version=%s %s %b\n\n" \
        "$GREEN" "$prefix" "$from_version" "$to_version" "$airgap_flag" "$NC"
    printf "Are you ready to continue? "
    confirmY
}

# rook_upgrade_merge_images_list will merge each list of images from the arguments into a single
# list and deduplicate the list.
function rook_upgrade_merge_images_list() {
    local images_list=
    while [ "$1" != "" ]; do
        images_list="$images_list $1"
        shift
    done
    echo "$images_list" | tr " " "\n" | sort | uniq | tr "\n" " " | xargs
}

# rook_upgrade_list_rook_ceph_images_in_manifest_file will list the rook/ceph images in the given
# manifest file.
function rook_upgrade_list_rook_ceph_images_in_manifest_file() {
    local manifest_file="$1"

    local image_list=
    # TODO: ask andrew l why only this image needs to be on remote nodes
    for image in $(grep "^image " "$manifest_file" | grep -F "rook/ceph" | awk '{print $3}' | tr '\n' ' ') ; do
        image_list=$image_list" $(canonical_image_name "$image")"
    done
    echo "$image_list" | xargs # trim whitespace
}

# rook_upgrade_step_versions returns a list of upgrade steps that need to be performed, based on
# $ROOK_STEP_VERSIONS, for use by other functions.
# e.g. "1.5.12\n1.6.11\n1.7.11"
function rook_upgrade_step_versions() {
    declare -a _step_versions=("${!1}")
    local from_version=$2
    local to_version=$3

    # check that both are major version 1
    if  [ "$(rook_upgrade_major_minor_to_major "$from_version")" != "1" ] || \
        [ "$(rook_upgrade_major_minor_to_major "$to_version")" != "1" ] ; then
        return 1
    fi

    local first_minor=
    local last_minor=
    first_minor=$(rook_upgrade_major_minor_to_minor "$from_version")
    last_minor=$(rook_upgrade_major_minor_to_minor "$to_version")

    if [ "${#_step_versions[@]}" -le "$last_minor" ]; then
        return 1
    fi

    local step=
    for (( step=first_minor ; step<=last_minor ; step++ )); do
        echo "${_step_versions[$step]}"
    done
}

# rook_upgrade_print_list_of_minor_upgrades prints message of minor versions that will be upgraded.
# e.g. "1.0.x to 1.1, 1.1 to 1.2, 1.2 to 1.3, and 1.3 to 1.4"
function rook_upgrade_print_list_of_minor_upgrades() {
    local from_version="$1"
    local to_version="$2"

    printf "This involves upgrading from "
    local first_minor=
    local last_minor=
    first_minor=$(rook_upgrade_major_minor_to_minor "$from_version")
    last_minor=$(rook_upgrade_major_minor_to_minor "$to_version")

    local minor=
    for (( minor=first_minor ; minor<last_minor ; minor++ )); do
        if [ "$minor" -gt "$first_minor" ]; then
            printf ", "
            if [ "$((minor + 1))" -eq "$last_minor" ]; then
                printf "and "
            fi
            printf "1.%s to 1.%s" "$minor" "$((minor + 1))"
        else
            printf "1.%s.x to 1.%s" "$minor" "$((minor + 1))"
        fi
    done
    printf ".\n"
}

# rook_upgrade_is_version_included returns 0 if the version is included in the range.
function rook_upgrade_is_version_included() {
    local from_version="$1"
    local to_version="$2"
    local current_version="$3"
    # if current_version is greater than from_version and current_version is less than or equal to to_version
    [ "$(rook_upgrade_compare_rook_versions "$current_version" "$from_version")" = "1" ] && \
    [ "$(rook_upgrade_compare_rook_versions "$current_version" "$to_version")" != "1" ]
}

# rook_upgrade_max_rook_version will return the greater of the two versions.
function rook_upgrade_max_rook_version() {
    local a="$1"
    local b="$2"
    if [ "$(rook_upgrade_compare_rook_versions "$a" "$b")" = "1" ]; then
        echo "$a"
    else
        echo "$b"
    fi
}

# rook_upgrade_compare_rook_versions prints 0 if the versions are equal, 1 if the first is greater,
# and -1 if the second is greater.
function rook_upgrade_compare_rook_versions() {
    local a="$1"
    local b="$2"

    local a_major=
    local b_major=
    a_major=$(rook_upgrade_major_minor_to_major "$a")
    b_major=$(rook_upgrade_major_minor_to_major "$b")

    if [ "$a_major" -lt "$b_major" ]; then
        echo "-1"
        return
    elif [ "$a_major" -gt "$b_major" ]; then
        echo "1"
        return
    fi

    local a_minor=
    local b_minor=
    a_minor=$(rook_upgrade_major_minor_to_minor "$a")
    b_minor=$(rook_upgrade_major_minor_to_minor "$b")

    if [ "$a_minor" -lt "$b_minor" ]; then
        echo "-1"
        return
    elif [ "$a_minor" -gt "$b_minor" ]; then
        echo "1"
        return
    fi

    echo "0"
}

# rook_upgrade_major_minor_to_major returns the major version of a major.minor version.
function rook_upgrade_major_minor_to_major() {
    echo "$1" | cut -d. -f1
}

# rook_upgrade_major_minor_to_minor returns the minor version of a major.minor version.
function rook_upgrade_major_minor_to_minor() {
    echo "$1" | cut -d. -f2
}

# rook_upgrade_rook_version_to_major_minor returns the major.minor version of a rook version.
function rook_upgrade_rook_version_to_major_minor() {
    echo "$1" | cut -d. -f1,2
}

# rook_upgrade_tasks_rook_upgrade is called by tasks.sh to upgrade rook.
function rook_upgrade_tasks_rook_upgrade() {
    local to_version=
    local airgap=
    rook_upgrade_tasks_params "$@"

    rook_upgrade_tasks_require_param "to-version" "$to_version"

    if [ "$airgap" = "1" ]; then
        export AIRGAP=1
    fi

    local to_version_major=
    local to_version_minor=
    to_version_major=$(rook_upgrade_major_minor_to_major "$to_version")
    to_version_minor=$(rook_upgrade_major_minor_to_minor "$to_version")

    # we must go to one version more than specified because the install logic will decrement the
    # version
    export ROOK_VERSION="$to_version_major.$((to_version_minor + 1)).999"

    export KUBECONFIG=/etc/kubernetes/admin.conf
    download_util_binaries
    
    rook_upgrade_maybe_report_upgrade_rook
}

# rook_upgrade_tasks_load_images is called from tasks.sh to load images on remote notes for the
# rook upgrade.
function rook_upgrade_tasks_load_images() {
    local from_version=
    local to_version=
    local airgap=
    rook_upgrade_tasks_params "$@"

    rook_upgrade_tasks_require_param "from-version" "$from_version"
    rook_upgrade_tasks_require_param "to-version" "$to_version"

    if [ "$airgap" = "1" ]; then
        export AIRGAP=1
    fi

    export KUBECONFIG=/etc/kubernetes/admin.conf
    download_util_binaries

    if ! rook_upgrade_addon_fetch_and_load "$from_version" "$to_version" ; then
        bail "Failed to load images"
    fi
}

# rook_upgrade_tasks_params parses the parameters for the rook upgrade tasks.
function rook_upgrade_tasks_params() {
    while [ "$1" != "" ]; do
        local _param=
        local _value=
        _param="$(echo "$1" | cut -d= -f1)"
        _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
        case $_param in
            from-version)
                from_version="$_value"
                ;;
            to-version)
                to_version="$_value"
                ;;
            airgap)
                airgap="1"
                ;;
            *)
                bail "Error: unknown parameter \"$_param\""
                ;;
        esac
        shift
    done
}

# rook_upgrade_tasks_require_param requires that the given parameter is set or bails.
function rook_upgrade_tasks_require_param() {
    local param="$1"
    local value="$2"
    if [ -z "$value" ]; then
        bail "Error: $param is required"
    fi
}
