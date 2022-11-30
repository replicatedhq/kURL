
ADDONS_HAVE_HOST_COMPONENTS=0
function addon_install() {
    local name=$1
    local version=$2

    if [ -z "$version" ]; then
        return 0
    fi

    logStep "Addon $name $version"

    report_addon_start "$name" "$version"

    rm -rf $DIR/kustomize/$name
    mkdir -p $DIR/kustomize/$name

    # if the addon has already been applied and addons are not being forcibly reapplied
    if addon_has_been_applied $name && [ -z "$FORCE_REAPPLY_ADDONS" ]; then
        export REPORTING_CONTEXT_INFO="addon already applied $name $version"
        # shellcheck disable=SC1090
        . $DIR/addons/$name/$version/install.sh

        if commandExists ${name}_already_applied; then
            ${name}_already_applied
        fi
        export REPORTING_CONTEXT_INFO=""
    else
        export REPORTING_CONTEXT_INFO="addon $name $version"
        # shellcheck disable=SC1090
        . $DIR/addons/$name/$version/install.sh
        # containerd is a special case because there is also a binary named containerd on the host
        if [ "$name" = "containerd" ]; then
            containerd_install
        else
            $name
        fi
        export REPORTING_CONTEXT_INFO=""
    fi

    addon_set_has_been_applied $name

    if commandExists ${name}_join; then
        ADDONS_HAVE_HOST_COMPONENTS=1
    fi
    if [ "$name" = "containerd" ]; then
        ADDONS_HAVE_HOST_COMPONENTS=1
    fi

    report_addon_success "$name" "$version"
}

function addon_fetch() {
    local name=$1
    local version=$2
    local s3Override=$3

    if [ -z "$version" ]; then
        return 0
    fi

    if [ "$AIRGAP" != "1" ]; then
        if [ -n "$s3Override" ]; then
            rm -rf $DIR/addons/$name/$version # Cleanup broken/incompatible addons from failed runs
            addon_fetch_cache "$name-$version.tar.gz" "$s3Override"
        elif [ -n "$DIST_URL" ]; then
            rm -rf $DIR/addons/$name/$version # Cleanup broken/incompatible addons from failed runs
            addon_fetch_cache "$name-$version.tar.gz"
        fi
    fi

    . $DIR/addons/$name/$version/install.sh
}

function addon_pre_init() {
    local name=$1

    if commandExists ${name}_pre_init; then
        ${name}_pre_init
    fi
}

function addon_post_init() {
    local name=$1

    if commandExists "${name}_post_init"; then
        "${name}_post_init"
    fi
}

function addon_preflight() {
    local name=$1
    local version=$2 # will be unset if addon is not part of the installer

    if [ -z "$name" ] || [ -z "$version" ]; then
        return
    fi

    local addonRoot="${DIR}/addons/${name}/${version}"
    if [ ! -d "$addonRoot" ]; then
        return
    fi

    local src="${addonRoot}/host-preflight.yaml"
    if [ -f "$src" ]; then
        echo "$src"
    fi

    if [ "${SKIP_SYSTEM_PACKAGE_INSTALL}" == "1" ]; then
        preflights_system_packages "$name" "$version"
    fi
}

function addon_join() {
    local name=$1
    local version=$2

    addon_load "$name" "$version"

    if commandExists ${name}_join; then
        logStep "Addon $name $version"
        ${name}_join
    fi
}

function addon_exists() {
    [ -d "$DIR/addons/$name/$version" ]
}

function addon_load() {
    local name=$1
    local version=$2

    if [ -z "$version" ]; then
        return 0
    fi

    load_images $DIR/addons/$name/$version/images
}

function addon_fetch_no_cache() {
    local url=$1

    local archiveName=$(basename $url)

    echo "Fetching $archiveName"
    curl -LO "$url"
    tar xf $archiveName
    rm $archiveName
}

function addon_fetch_cache() {
    local package=$1
    local url_override=$2

    package_download "${package}" "${url_override}"

    tar xf "$(package_filepath "${package}")"

    # rm $archiveName
}

function addon_outro() {
    if [ -n "$PROXY_ADDRESS" ]; then
        ADDONS_HAVE_HOST_COMPONENTS=1
    fi

    if [ "$ADDONS_HAVE_HOST_COMPONENTS" = "1" ] && kubernetes_has_remotes; then
        local common_flags
        common_flags="${common_flags}$(get_docker_registry_ip_flag "${DOCKER_REGISTRY_IP}")"
        if [ -n "$ADDITIONAL_NO_PROXY_ADDRESSES" ]; then
            common_flags="${common_flags}$(get_additional_no_proxy_addresses_flag "1" "${ADDITIONAL_NO_PROXY_ADDRESSES}")"
        fi
        common_flags="${common_flags}$(get_additional_no_proxy_addresses_flag "${PROXY_ADDRESS}" "${SERVICE_CIDR},${POD_CIDR}")"
        common_flags="${common_flags}$(get_kurl_install_directory_flag "${KURL_INSTALL_DIRECTORY_FLAG}")"
        common_flags="${common_flags}$(get_force_reapply_addons_flag)"
        common_flags="${common_flags}$(get_skip_system_package_install_flag)"
        common_flags="${common_flags}$(get_exclude_builtin_host_preflights_flag)"
        common_flags="${common_flags}$(get_remotes_flags)"

        printf "\n${YELLOW}Run this script on all remote nodes to apply changes${NC}\n"
        if [ "$AIRGAP" = "1" ]; then
            printf "\n\t${GREEN}cat ./upgrade.sh | sudo bash -s airgap${common_flags}${NC}\n\n"
        else
            local prefix=
            prefix="$(build_installer_prefix "${INSTALLER_ID}" "${KURL_VERSION}" "${KURL_URL}" "${PROXY_ADDRESS}")"

            printf "\n\t${GREEN}${prefix}upgrade.sh | sudo bash -s${common_flags}${NC}\n\n"
        fi

        if [ "${KURL_IGNORE_REMOTE_UPGRADE_PROMPT}" != "1" ]; then
            if prompts_can_prompt ; then
                echo "Press enter to proceed"
                prompt
            fi
        else
            logWarn "Remote upgrade script prompt explicitly ignored"
        fi
    fi

    while read -r name; do
        if commandExists ${name}_outro; then
            ${name}_outro
        fi
    done < <(find addons/ -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
}

function addon_cleanup() {
    rm -rf "${DIR}/addons"
}

function addon_has_been_applied() {
    local name=$1

    if [ "$name" = "containerd" ]; then
        if [ -f $DIR/containerd-last-applied ]; then
            last_applied=$(cat $DIR/containerd-last-applied)
        fi
    else
        last_applied=$(kubectl get configmap -n kurl kurl-last-config -o jsonpath="{.data.addons-$name}")
    fi

    current=$(get_addon_config "$name" | base64 -w 0)

    if [[ "$current" == "" ]] ; then
        # current should never be the empty string - it should at least contain the version - so this indicates an error
        # it would be better to reinstall unnecessarily rather than skip installing, so we report that the addon has not been applied
        return 1
    fi

    if [[ "$last_applied" == "$current" ]] ; then
        return 0
    fi

    return 1
}

function addon_set_has_been_applied() {
    local name=$1
    current=$(get_addon_config "$name" | base64 -w 0)

    if [ "$name" = "containerd" ]; then
        echo "$current" > $DIR/containerd-last-applied
    else
        kubectl patch configmaps -n kurl kurl-current-config --type merge -p "{\"data\":{\"addons-$name\":\"$current\"}}"
    fi
}

# check if the files are already present - if they are, use that
# if they are not, prompt the user to provide them
# if the user does not provide the files, return 1
function addon_fetch_airgap() {
    local name=$1
    local version=$2
    local package="$name-$version.tar.gz"

    if [ -f "$(package_filepath "${package}")" ]; then
        # the package already exists, no need to download it
        printf "The package %s %s is already available locally.\n" "$name" "$version"
    else
        # prompt the user to give us the package
        printf "The package %s %s is not available locally, and is required.\n" "$name" "$version"
        printf "You can download it from %s with the following command:\n" "$(get_dist_url)/${package}"
        printf "\n${GREEN}    curl -LO %s${NC}\n\n" "$(get_dist_url)/${package}"

        if ! prompts_can_prompt; then
            # we can't ask the user to give us the file because there are no prompts, but we can say where to put it for a future run
            printf "Please move this file to /var/lib/kurl/%s before rerunning the installer.\n" "$(package_filepath "${package}")"
            return 1
        fi

        printf "If you have this file, please provide the path to the file on the server.\n"
        printf "If you do not have the file, leave the prompt empty and this package will be skipped.\n"
        printf "%s %s filepath: " "$name" "$version"
        prompt
        if [ -n "$PROMPT_RESULT" ]; then
            local loadedPackagePath="$PROMPT_RESULT"
            cp "$loadedPackagePath" "$(package_filepath "${package}")"
        else
            printf "Skipping package %s %s\n" "$name" "$version"
            printf "You can provide the path to this file the next time the installer is run,"
            printf "or move it to %s to be detected automatically.\n" "$(package_filepath "${package}")"
            return 1
        fi
    fi

    printf "Unpacking %s %s...\n" "$name" "$version"
    tar xf "$(package_filepath "${package}")"

    . $DIR/addons/$name/$version/install.sh

    return 0
}
