

INSTALLATION_ID=
function report_install_start() {
    # report that the install started
    # this includes the install ID, time, kurl URL, HA status, server CPU count and memory size, and linux distribution name + version.

    # if airgapped, don't create an installation ID and return early
    if [ "$AIRGAP" == "1" ]; then
        return 0
    fi

    INSTALLATION_ID=$(< /dev/urandom tr -dc a-z0-9 | head -c16)
    local started=$(date -u +"%Y-%m-%dT%H:%M:%SZ") # rfc3339

    curl -s --output /dev/null -H 'Content-Type: application/json' --max-time 5 \
        -d "{\"started\": \"$started\", \"os\": \"$LSB_DIST $DIST_VERSION\", \"kernel_version\": \"$KERNEL_MAJOR.$KERNEL_MINOR\", \"kurl_url\": \"$KURL_URL\", \"installer_id\": \"$INSTALLER_ID\", \"testgrid_id\": \"$TEST_ID\"}" \
        $REPLICATED_APP_URL/kurl_metrics/start_install/$INSTALLATION_ID
}

function report_install_success() {
    # report that the install finished successfully

    # if INSTALLATION_ID is empty reporting is disabled
    if [ -z "$INSTALLATION_ID" ]; then
        return 0
    fi

    local completed=$(date -u +"%Y-%m-%dT%H:%M:%SZ") # rfc3339

    curl -s --output /dev/null -H 'Content-Type: application/json' --max-time 5 \
        -d "{\"finished\": \"$completed\"}" \
        $REPLICATED_APP_URL/kurl_metrics/finish_install/$INSTALLATION_ID
}

function report_addon_start() {
    # report that an addon started installation
    local name=$1
    local version=$2

    # if INSTALLATION_ID is empty reporting is disabled
    if [ -z "$INSTALLATION_ID" ]; then
        return 0
    fi

    local started=$(date -u +"%Y-%m-%dT%H:%M:%SZ") # rfc3339

    curl -s --output /dev/null -H 'Content-Type: application/json' --max-time 5 \
        -d "{\"started\": \"$started\", \"addon_version\": \"$version\"}" \
        $REPLICATED_APP_URL/kurl_metrics/start_addon/$INSTALLATION_ID/$name
}

function report_addon_success() {
    # report that an addon installed successfully
    local name=$1
    local version=$2

    # if INSTALLATION_ID is empty reporting is disabled
    if [ -z "$INSTALLATION_ID" ]; then
        return 0
    fi

    local completed=$(date -u +"%Y-%m-%dT%H:%M:%SZ") # rfc3339

    curl -s --output /dev/null -H 'Content-Type: application/json' --max-time 5 \
        -d "{\"finished\": \"$completed\", \"addon_version\": \"$version\"}" \
        $REPLICATED_APP_URL/kurl_metrics/finish_addon/$INSTALLATION_ID/$name
}
