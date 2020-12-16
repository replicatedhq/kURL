

INSTALLATION_ID=
TESTGRID_ID=
function report_install_start() {
    # report that the install started
    # this includes the install ID, time, kurl URL, HA status, server CPU count and memory size, and linux distribution name + version.

    # if airgapped, don't create an installation ID and return early
    if [ "$AIRGAP" == "1" ]; then
        return 0
    fi

    INSTALLATION_ID=$(< /dev/urandom tr -dc a-z0-9 | head -c16)
    local started=$(date -u +"%Y-%m-%dT%H:%M:%SZ") # rfc3339

    if [ -f "/tmp/testgrid-id" ]; then
        TESTGRID_ID=$(cat /tmp/testgrid-id)
    fi

    curl -s --output /dev/null -H 'Content-Type: application/json' --max-time 5 \
        -d "{\"started\": \"$started\", \"os\": \"$LSB_DIST $DIST_VERSION\", \"kernel_version\": \"$KERNEL_MAJOR.$KERNEL_MINOR\", \"kurl_url\": \"$KURL_URL\", \"installer_id\": \"$INSTALLER_ID\", \"testgrid_id\": \"$TESTGRID_ID\"}" \
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
        -d "{\"started\": \"$started\", \"addon_version\": \"$version\", \"testgrid_id\": \"$TESTGRID_ID\"}" \
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
        -d "{\"finished\": \"$completed\"}" \
        $REPLICATED_APP_URL/kurl_metrics/finish_addon/$INSTALLATION_ID/$name
}

# trap ctrl+c (SIGINT) and handle it by asking for a support bundle
trap ctrl_c SIGINT
function ctrl_c() {
    trap - SIGINT # reset SIGINT handler to default - someone should be able to ctrl+c the support bundle collector

    printf "${YELLOW}Trapped ctrl+c${NC}\n"
    collect_support_bundle

    exit 1 # exit with error
}

function addon_install_fail() {
    # report that an addon failed to install successfully
    local name=$1
    local version=$2

    # if INSTALLATION_ID is empty reporting is disabled
    if [ -z "$INSTALLATION_ID" ]; then
        return 1 # return error because the addon in question did too
    fi

    local completed=$(date -u +"%Y-%m-%dT%H:%M:%SZ") # rfc3339

    curl -s --output /dev/null -H 'Content-Type: application/json' --max-time 5 \
        -d "{\"finished\": \"$completed\"}" \
        $REPLICATED_APP_URL/kurl_metrics/fail_addon/$INSTALLATION_ID/$name

    # provide an option for a user to provide a support bundle
    printf "${YELLOW}Addon ${name} ${version} failed to install${NC}\n"
    collect_support_bundle

    return 1 # return error because the addon in question did too
}

function collect_support_bundle() {
    trap - SIGINT # reset SIGINT handler to default - someone should be able to ctrl+c the support bundle collector

    printf "${YELLOW}Would you like to provide a support bundle?${NC}\n"
    if ! confirmY "-t 120"; then
        return 0
    fi

    printf "${YELLOW}Please provide an email address for us to reach you:${NC}\n"
    promptTimeout "-t 120"
    local email_address=""
    if [ -n "$PROMPT_RESULT" ]; then
        email_address="$PROMPT_RESULT"
    fi

    printf "${YELLOW}Could you provide a quick description of the issue you encountered?${NC}\n"
    promptTimeout "-t 120"
    local issue_description=""
    if [ -n "$PROMPT_RESULT" ]; then
        issue_description="$PROMPT_RESULT"
    fi

    # collect support bundle
    printf "Collecting support bundle now:"
    kubectl support-bundle https://kots.io

    # find the support bundle filename
    local support_bundle_filename=$(find . -type f -name "support-bundle-*.tar.gz")

    curl 'https://support-bundle-secure-upload.replicated.com/v1/upload' \
        -H 'accept: application/json, text/plain, */*' \
        -X POST \
        -H "Content-Type: multipart/form-data" \
        -F "data={\"first_name\":\"kurl.sh\",\"last_name\":\"installer\",\"email_address\":\"${email_address}\",\"company\":\"\",\"description\":\"${issue_description}\"}" \
        -F "file=@${support_bundle_filename}" \
        --compressed
}