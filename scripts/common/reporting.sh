

INSTALLATION_ID=
function report_install_start() {
    # report that the install started
    # this includes the install ID, time, kurl URL, HA status, server CPU count and memory size, and linux distribution name + version.

    # if airgapped, don't create an installation ID and return early
    if [ -z "$version" ]; then
        return 0
    fi

    INSTALLATION_ID=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c16)
    local started=$(date -u +"%Y-%m-%dT%H:%M:%SZ") # rfc3339


    local payload=#TODO
}

function report_install_success() {
    # report that the install finished successfully

    # if INSTALLATION_ID is empty reporting is disabled
    if [ -z "$INSTALLATION_ID" ]; then
        return 0
    fi

    local completed=$(date -u +"%Y-%m-%dT%H:%M:%SZ") # rfc3339
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
}