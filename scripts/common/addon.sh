
function addon_for_each() {
    local cmd="$1"

    $cmd aws "$AWS_VERSION"
    $cmd nodeless "$NODELESS_VERSION"
    $cmd calico "$CALICO_VERSION"
    $cmd weave "$WEAVE_VERSION"
    $cmd rook "$ROOK_VERSION"
    $cmd openebs "$OPENEBS_VERSION"
    $cmd minio "$MINIO_VERSION"
    $cmd contour "$CONTOUR_VERSION"
    $cmd registry "$REGISTRY_VERSION"
    $cmd prometheus "$PROMETHEUS_VERSION"
    $cmd kotsadm "$KOTSADM_VERSION"
    $cmd velero "$VELERO_VERSION"
    $cmd fluentd "$FLUENTD_VERSION"
    $cmd ekco "$EKCO_VERSION"
    $cmd collectd "$COLLECTD_VERSION"
    $cmd cert-manager "$CERT_MANAGER_VERSION"
    $cmd metrics-server "$METRICS_SERVER_VERSION"
}

ADDONS_HAVE_HOST_COMPONENTS=0
function addon_install() {
    local name=$1
    local version=$2

    if [ -z "$version" ]; then
        return 0
    fi

    logStep "Addon $name $version"

    rm -rf $DIR/kustomize/$name
    mkdir -p $DIR/kustomize/$name

    . $DIR/addons/$name/$version/install.sh

    $name

    if commandExists ${name}_join; then
        ADDONS_HAVE_HOST_COMPONENTS=1
    fi
}

function addon_pre_init() {
    local name=$1
    local version=$2

    if [ -z "$version" ]; then
        return 0
    fi

    if [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        echo "Fetching $name-$version.tar.gz"
        curl -sSLO "$DIST_URL/$name-$version.tar.gz"
        tar xf $name-$version.tar.gz
        rm $name-$version.tar.gz
    fi

    . $DIR/addons/$name/$version/install.sh

    if commandExists ${name}_pre_init; then
        ${name}_pre_init
    fi
}

function addon_join() {
    local name=$1
    local version=$2

    if [ -z "$version" ]; then
        return 0
    fi

    if [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        curl -sSLO "$DIST_URL/$name-$version.tar.gz"
        tar xf $name-$version.tar.gz
        rm $name-$version.tar.gz
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

function addon_outro() {
    if [ -n "$PROXY_ADDRESS" ]; then
        ADDONS_HAVE_HOST_COMPONENTS=1
    fi

    if [ "$ADDONS_HAVE_HOST_COMPONENTS" = "1" ] && kubernetes_has_remotes; then
        local dockerRegistryIP=""
        if [ -n "$DOCKER_REGISTRY_IP" ]; then
            dockerRegistryIP=" docker-registry-ip=$DOCKER_REGISTRY_IP"
        fi

        local proxyFlag=""
        local noProxyAddrs=""
        if [ -n "$PROXY_ADDRESS" ]; then
            proxyFlag=" -x $PROXY_ADDRESS"
            noProxyAddrs=" additional-no-proxy-addresses=${SERVICE_CIDR},${POD_CIDR}"
        fi

        local prefix="curl -sSL${proxyFlag} $KURL_URL/$INSTALLER_ID/"
        if [ -z "$KURL_URL" ]; then
            prefix="cat "
        fi

        printf "\n${YELLOW}Run this script on all remote nodes to apply changes${NC}\n"
        printf "\n\t${GREEN}${prefix}upgrade.sh | sudo bash -s${dockerRegistryIP}${noProxyAddrs}${NC}\n\n"
        printf "Press enter to proceed\n"
        prompt

    fi

    while read -r name; do
        if commandExists ${name}_outro; then
            ${name}_outro
        fi
    done < <(find addons/ -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
}
