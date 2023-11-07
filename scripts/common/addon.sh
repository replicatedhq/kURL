#!/bin/bash

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
    
    export REPORTING_CONTEXT_INFO="addon $name $version"

    # shellcheck disable=SC1090
    addon_source "$name" "$version"

    # containerd is a special case because there is also a binary named containerd on the host
    if [ "$name" = "containerd" ]; then
        containerd_install
    else
        $name
    fi
    export REPORTING_CONTEXT_INFO=""

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

    addon_source "$name" "$version"
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
    local name=$1
    local version=$2
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
    tar xf $archiveName --no-same-owner
    rm $archiveName
}

function addon_fetch_cache() {
    local package=$1
    local url_override=$2

    package_download "${package}" "${url_override}"

    tar xf "$(package_filepath "${package}")"  --no-same-owner

    # rm $archiveName
}

# addon_fetch_airgap checks if the files are already present - if they are, use that
# if they are not, prompt the user to provide them
# if the user does not provide the files, bail
function addon_fetch_airgap() {
    local name=$1
    local version=$2
    local package_name="$name-$version.tar.gz"
    local package_path=
    package_path="$(package_filepath "$package_name")"

    if [ -f "$package_path" ]; then
        # the package already exists, no need to download it
        printf "The package %s %s is already available locally.\n" "$name" "$version"
    else
        package_path="$(find assets/*"$name-$version"*.tar.gz 2>/dev/null | head -n 1)"
        if [ -n "$package_path" ]; then
            # the package already exists, no need to download it
            printf "The package %s is already available locally.\n" "$(basename "$package_path")"
        else
            # prompt the user to give us the package
            printf "The package %s %s is not available locally, and is required.\n" "$name" "$version"
            printf "\nYou can download it with the following command:\n"
            printf "\n${GREEN}    curl -LO %s${NC}\n\n" "$(get_dist_url)/$package_name"

            addon_fetch_airgap_prompt_for_package "$package_name"
        fi
    fi

    printf "Unpacking %s %s...\n" "$name" "$version"
    tar xf "$package_path" --no-same-owner

    # do not source the addon here as the kubernetes "addon" uses this function but is not an addon
}

# addon_fetch_multiple_airgap checks if the files are already present - if they are, use that
# if they are not, prompt the user to provide them as a single package
# if the user does not provide the files, bail
# exports the package filepath for later cleanup
function addon_fetch_multiple_airgap() {
    local addon_versions=( "$@" )
    local missing_addon_versions=()
    export AIRGAP_MULTI_ADDON_PACKAGE_PATH=
    for addon_version in "${addon_versions[@]}"; do
        local name=, version=
        name=$(echo "$addon_version" | cut -d- -f1)
        version=$(echo "$addon_version" | cut -d- -f2)
        local package_name="$name-$version.tar.gz"
        local package_path=
        package_path="$(package_filepath "$package_name")"
        if [ -f "$package_path" ]; then
            # the package already exists, no need to download it
            printf "The package %s %s is already available locally.\n" "$name" "$version"

            printf "Unpacking %s...\n" "$package_name"
            if ! tar xf "$package_path" --no-same-owner ; then
                bail "Failed to unpack $package_name"
            fi
        else
            # the package does not exist, add it to the list of missing packages
            missing_addon_versions+=("$addon_version")
        fi
    done

    if [ "${#missing_addon_versions[@]}" -gt 0 ]; then
        local package_list=
        package_list=$(printf ",%s" "${missing_addon_versions[@]}") # join with commas
        package_list="${package_list:1}"
        local package_name="$package_list.tar.gz"
        local package_path=
        package_path="$(package_filepath "$package_name")"
        AIRGAP_MULTI_ADDON_PACKAGE_PATH="$package_path"

        if [ -f "$package_path" ]; then
            # the package already exists, no need to download it
            printf "The package %s is already available locally.\n" "$package_name"
        else
            local bundle_url="$KURL_URL/bundle"
            if [ -n "$KURL_VERSION" ]; then
                bundle_url="$bundle_url/version/$KURL_VERSION"
            fi
            bundle_url="$bundle_url/$INSTALLER_ID/packages/$package_name"

            printf "The following packages are not available locally, and are required:\n"
            # prompt the user to give us the packages
            for addon_version in "${missing_addon_versions[@]}"; do
                printf "    %s\n" "$addon_version.tar.gz"
            done
            printf "\nYou can download them with the following command:\n"
            printf "\n${GREEN}    curl -LO %s${NC}\n\n" "$bundle_url"

            addon_fetch_airgap_prompt_for_package "$package_name"
        fi

        printf "Unpacking %s...\n" "$package_name"
        if ! tar xf "$package_path" --no-same-owner ; then
            bail "Failed to unpack $package_name"
        fi

        # do not source the addon here as we are loading multiple addons that may conflict
        # also the kubernetes "addon" uses this function but is not an addon
    fi
}

# addon_fetch_airgap_prompt_for_package prompts the user do download a package
function addon_fetch_airgap_prompt_for_package() {
    local package_name="$1"
    local package_path=
    package_path=$(package_filepath "$package_name")

    if ! prompts_can_prompt; then
        # we can't ask the user to give us the file because there are no prompts, but we can say where to put it for a future run
        bail "Please move this file to $KURL_INSTALL_DIRECTORY/$package_path before rerunning the installer."
    fi

    printf "Please provide the path to the file on the server.\n"
    printf "Absolute path to file: "
    prompt
    if [ -n "$PROMPT_RESULT" ]; then
        local loaded_package_path="$PROMPT_RESULT"
        if [ ! -f "$loaded_package_path" ]; then
            bail "The file $loaded_package_path does not exist."
        fi
        mkdir -p "$(dirname "$package_path")"
        log "Copying $loaded_package_path to $package_path"
        cp "$loaded_package_path" "$package_path"
    else
        logFail "Package $package_name not provided."
        logFail "You can provide the path to this file the next time the installer is run,"
        bail "or move it to $KURL_INSTALL_DIRECTORY/$package_path to be detected automatically.\n"
    fi
}

function addon_outro() {
    if [ -n "$PROXY_ADDRESS" ]; then
        ADDONS_HAVE_HOST_COMPONENTS=1
    fi

    if [ "$ADDONS_HAVE_HOST_COMPONENTS" = "1" ] && kubernetes_has_remotes; then
        local common_flags
        common_flags="${common_flags}$(get_docker_registry_ip_flag "${DOCKER_REGISTRY_IP}")"

        local no_proxy_addresses=""
        [ -n "$ADDITIONAL_NO_PROXY_ADDRESSES" ] && no_proxy_addresses="$ADDITIONAL_NO_PROXY_ADDRESSES"
        [ -n "${SERVICE_CIDR}" ] && no_proxy_addresses="${no_proxy_addresses:+$no_proxy_addresses,}${SERVICE_CIDR}"
        [ -n "${POD_CIDR}" ] && no_proxy_addresses="${no_proxy_addresses:+$no_proxy_addresses,}${POD_CIDR}"
        [ -n "$no_proxy_addresses" ] && common_flags="${common_flags}$(get_additional_no_proxy_addresses_flag 1 "$no_proxy_addresses")"

        common_flags="${common_flags}$(get_kurl_install_directory_flag "${KURL_INSTALL_DIRECTORY_FLAG}")"
        common_flags="${common_flags}$(get_skip_system_package_install_flag)"
        common_flags="${common_flags}$(get_exclude_builtin_host_preflights_flag)"
        common_flags="${common_flags}$(get_remotes_flags)"

        printf "\n${YELLOW}Run this script on all remote nodes to apply changes${NC}\n"
        if [ "$AIRGAP" = "1" ]; then
            local command=
            command=$(printf "cat ./upgrade.sh | sudo bash -s airgap${common_flags}")
            echo "$command yes" > "$DIR/remotes/allnodes"

            printf "\n\t${GREEN}%s${NC}\n\n" "$command"
        else
            local prefix=
            prefix="$(build_installer_prefix "${INSTALLER_ID}" "${KURL_VERSION}" "${KURL_URL}" "${PROXY_ADDRESS}" "${PROXY_HTTPS_ADDRESS}")"

            local command=
            command=$(printf "${prefix}upgrade.sh | sudo bash -s${common_flags}")
            echo "$command yes" > "$DIR/remotes/allnodes"

            printf "\n\t${GREEN}%s${NC}\n\n" "$command"
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

function addon_source() {
    local name=$1
    local version=$2
    # shellcheck disable=SC1090
    . "$DIR/addons/$name/$version/install.sh"
}
