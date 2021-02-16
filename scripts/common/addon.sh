
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

    . $DIR/addons/$name/$version/install.sh || addon_install_fail "$name" "$version"

    $name || addon_install_fail "$name" "$version"

    if commandExists ${name}_join; then
        ADDONS_HAVE_HOST_COMPONENTS=1
    fi

    report_addon_success "$name" "$version"
}

function addon_pre_init() {
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
            addon_fetch "$name-$version.tar.gz"
        fi
    fi

    . $DIR/addons/$name/$version/install.sh

    if commandExists ${name}_pre_init; then
        ${name}_pre_init
    fi
}

function addon_join() {
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
            addon_fetch "$name-$version.tar.gz"
        fi
    fi

    addon_load "$name" "$version"

    . $DIR/addons/$name/$version/install.sh

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

function addon_fetch() {
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
        local proxyFlag=""
        if [ -n "$PROXY_ADDRESS" ]; then
            proxyFlag=" -x $PROXY_ADDRESS"
        fi

        local prefix="curl -sSL${proxyFlag} $KURL_URL/$INSTALLER_ID/"
        if [ "$AIRGAP" = "1" ] || [ -z "$KURL_URL" ]; then
            prefix="cat "
        fi

        local common_flags
        common_flags="${common_flags}$(get_docker_registry_ip_flag "${DOCKER_REGISTRY_IP}")"
        common_flags="${common_flags}$(get_additional_no_proxy_addresses_flag "${PROXY_ADDRESS}" "${SERVICE_CIDR},${POD_CIDR}")"
        common_flags="${common_flags}$(get_kurl_install_directory_flag "${KURL_INSTALL_DIRECTORY_FLAG}")"

        printf "\n${YELLOW}Run this script on all remote nodes to apply changes${NC}\n"
        if [ "$AIRGAP" = "1" ]; then
            printf "\n\t${GREEN}${prefix}upgrade.sh | sudo bash -s airgap${common_flags}${NC}\n\n"
        else
            printf "\n\t${GREEN}${prefix}upgrade.sh | sudo bash -s${common_flags}${NC}\n\n"
        fi
        printf "Press enter to proceed\n"
        prompt

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
