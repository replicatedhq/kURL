
function addon_for_each() {
    local cmd="$1"

    $cmd aws "$AWS_VERSION"
    $cmd nodeless "$NODELESS_VERSION"
    $cmd calico "$CALICO_VERSION" "$CALICO_S3_OVERRIDE"
    $cmd weave "$WEAVE_VERSION" "$WEAVE_S3_OVERRIDE"
    $cmd rook "$ROOK_VERSION" "$ROOK_S3_OVERRIDE"
    $cmd openebs "$OPENEBS_VERSION" "$OPENEBS_S3_OVERRIDE"
    $cmd minio "$MINIO_VERSION" "$MINIO_S3_OVERRIDE"
    $cmd contour "$CONTOUR_VERSION" "$CONTOUR_S3_OVERRIDE"
    $cmd registry "$REGISTRY_VERSION" "$REGISTRY_S3_OVERRIDE"
    $cmd prometheus "$PROMETHEUS_VERSION" "$PROMETHEUS_S3_OVERRIDE"
    $cmd kotsadm "$KOTSADM_VERSION" "$KOTSADM_S3_OVERRIDE"
    $cmd velero "$VELERO_VERSION" "$VELERO_S3_OVERRIDE"
    $cmd fluentd "$FLUENTD_VERSION" "$FLUENTD_S3_OVERRIDE"
    $cmd ekco "$EKCO_VERSION" "$EKCO_S3_OVERRIDE"
    $cmd collectd "$COLLECTD_VERSION" "$COLLECTD_S3_OVERRIDE"
    $cmd cert-manager "$CERT_MANAGER_VERSION" "$CERT_MANAGER_S3_OVERRIDE"
    $cmd metrics-server "$METRICS_SERVER_VERSION" "$METRICS_SERVER_S3_OVERRIDE"
}

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
            addon_fetch "$s3Override"
        elif [ -n "$DIST_URL" ]; then
            addon_fetch "$DIST_URL/$name-$version.tar.gz"
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
            addon_fetch "$s3Override"
        elif [ -n "$DIST_URL" ]; then
            addon_fetch "$DIST_URL/$name-$version.tar.gz"
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

function addon_fetch() {
    local url=$1

    local archiveName=$(basename $url)

    echo "Fetching $archiveName"   
    curl -sSLO "$url"
    tar xf $archiveName
    rm $archiveName
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
        if [ "$AIRGAP" = "1" ] || [ -z "$KURL_URL" ]; then
            prefix="cat "
        fi

        printf "\n${YELLOW}Run this script on all remote nodes to apply changes${NC}\n"
        if [ "$AIRGAP" = "1" ]; then
            printf "\n\t${GREEN}${prefix}upgrade.sh | sudo bash -s airgap ${dockerRegistryIP}${noProxyAddrs}${NC}\n\n"
        else
            printf "\n\t${GREEN}${prefix}upgrade.sh | sudo bash -s${dockerRegistryIP}${noProxyAddrs}${NC}\n\n"
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
