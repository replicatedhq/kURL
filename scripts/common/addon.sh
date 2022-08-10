
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
            addon_fetch_no_cache "$s3Override"
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

    package_download "${package}"

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
