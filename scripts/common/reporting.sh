
REPORTING_CONTEXT_INFO=""

INSTALLATION_ID=
TESTGRID_ID=
KURL_CLUSTER_UUID=
function report_install_start() {
    # report that the install started
    # this includes the install ID, time, kurl URL, and linux distribution name + version.

    if [ -f "/tmp/testgrid-id" ]; then
        TESTGRID_ID=$(cat /tmp/testgrid-id)
    fi

    # if airgapped, don't create an installation ID and return early
    if [ "$AIRGAP" == "1" ]; then
        return 0
    fi

    # if DISABLE_REPORTING is set, don't create an installation ID (which thus disables all the other reporting calls) and return early
    if [ "${DISABLE_REPORTING}" = "1" ]; then
        return 0
    fi

    INSTALLATION_ID=$(< /dev/urandom tr -dc a-z0-9 | head -c16)
    local started=$(date -u +"%Y-%m-%dT%H:%M:%SZ") # rfc3339

     # Determine if it is the first kurl install
     local is_upgrade="false"
     if kubernetes_resource_exists kube-system configmap kurl-config; then
         local is_upgrade="true"
     fi

     # get the kurl_cluster_id
     attempt_get_cluster_id

     curl -s --output /dev/null -H 'Content-Type: application/json' --max-time 5 \
        -d "{\
        \"started\": \"$started\", \
        \"os\": \"$LSB_DIST $DIST_VERSION\", \
        \"kernel_version\": \"$KERNEL_MAJOR.$KERNEL_MINOR\", \
        \"kurl_url\": \"$KURL_URL\", \
        \"installer_id\": \"$INSTALLER_ID\", \
        \"testgrid_id\": \"$TESTGRID_ID\", \
        \"machine_id\": \"$MACHINE_ID\", \
        \"kurl_instance_uuid\": \"$KURL_INSTANCE_UUID\", \
        \"is_upgrade\": $is_upgrade, \
        \"is_ha_cluster\": \"$HA_CLUSTER\", \
        \"num_processors\": \"$(nproc)\", \
        \"memory_size_kb\": \"$(cat /proc/meminfo | grep MemTotal | awk '{print $2}')\", \
        \"kurl_cluster_uuid\": \"$KURL_CLUSTER_UUID\" \
        }" \
        $REPLICATED_APP_URL/kurl_metrics/start_install/$INSTALLATION_ID || true
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
        $REPLICATED_APP_URL/kurl_metrics/finish_install/$INSTALLATION_ID || true
}

function report_install_fail() {
    # report that the install failed
    local cause=$1

    # if INSTALLATION_ID is empty reporting is disabled
    if [ -z "$INSTALLATION_ID" ]; then
        return 0
    fi

    local completed=$(date -u +"%Y-%m-%dT%H:%M:%SZ") # rfc3339

    curl -s --output /dev/null -H 'Content-Type: application/json' --max-time 5 \
        -d "{\"finished\": \"$completed\", \"cause\": \"$cause\"}" \
        $REPLICATED_APP_URL/kurl_metrics/fail_install/$INSTALLATION_ID || true
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
        $REPLICATED_APP_URL/kurl_metrics/start_addon/$INSTALLATION_ID/$name || true
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
        $REPLICATED_APP_URL/kurl_metrics/finish_addon/$INSTALLATION_ID/$name || true
}

function ctrl_c() {
    trap - SIGINT # reset SIGINT handler to default - someone should be able to ctrl+c the support bundle collector
    read line file <<<$(caller)

    printf "${YELLOW}Trapped ctrl+c on line $line${NC}\n"

    local totalStack
    totalStack=$(stacktrace)

    local infoString="with stack $totalStack - bin utils $KURL_BIN_UTILS_FILE - context $REPORTING_CONTEXT_INFO"

    if [ -z "$SUPPORT_BUNDLE_READY" ]; then
        report_install_fail "trapped ctrl+c before completing k8s install $infoString"
        exit 1
    fi

    report_install_fail "trapped ctrl+c $infoString"

    collect_support_bundle

    exit 1 # exit with error
}

# unused
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
        $REPLICATED_APP_URL/kurl_metrics/fail_addon/$INSTALLATION_ID/$name || true

    # provide an option for a user to provide a support bundle
    printf "${YELLOW}Addon ${name} ${version} failed to install${NC}\n"
    collect_support_bundle

    return 1 # return error because the addon in question did too
}

# unused
function addon_install_fail_nobundle() {
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
        $REPLICATED_APP_URL/kurl_metrics/fail_addon/$INSTALLATION_ID/$name || true

    return 1 # return error because the addon in question did too
}

function collect_support_bundle() {
    trap - SIGINT # reset SIGINT handler to default - someone should be able to ctrl+c the support bundle collector
    return 0 # disabled for now

    # if someone has set ASSUME_YES, we shouldn't automatically upload a support bundle
    if [ "$ASSUME_YES" = "1" ]; then
        return 0
    fi
    if ! prompts_can_prompt ; then
        return 0
    fi

    printf "${YELLOW}Would you like to provide a support bundle to aid us in avoiding similar errors in the future?${NC}\n"
    if ! confirmN; then
        return 0
    fi

    printf "${YELLOW}Please provide your work email address for our records (this is not a support ticket):${NC}\n"
    prompt
    local email_address=""
    if [ -n "$PROMPT_RESULT" ]; then
        email_address="$PROMPT_RESULT"
    fi

    printf "${YELLOW}Could you provide a quick description of the issue you encountered?${NC}\n"
    prompt
    local issue_description=""
    if [ -n "$PROMPT_RESULT" ]; then
        issue_description="$PROMPT_RESULT"
    fi

    # collect support bundle
    printf "Collecting support bundle now:"
    kubectl support-bundle https://kots.io

    # find the support bundle filename
    local support_bundle_filename=$(find . -type f -name "support-bundle-*.tar.gz" | sort -r | head -n 1)

    curl 'https://support-bundle-secure-upload.replicated.com/v1/upload' \
        -H 'accept: application/json, text/plain, */*' \
        -X POST \
        -H "Content-Type: multipart/form-data" \
        -F "data={\"first_name\":\"kurl.sh\",\"last_name\":\"installer\",\"email_address\":\"${email_address}\",\"company\":\"\",\"description\":\"${issue_description}\"}" \
        -F "file=@${support_bundle_filename}" \
        --compressed

    printf "\nSupport bundle uploaded!\n"
}

function trap_report_error {
    if [[ ! $- =~ e ]]; then # if errexit is not set (set -e), don't report an error here
        return 0
    fi

    trap - ERR # reset the error handler to default in case there are errors within this function
    read line file <<<$(caller)
    printf "${YELLOW}An error occurred on line $line${NC}\n"

    local totalStack
    totalStack=$(stacktrace)

    report_install_fail "An error occurred with stack $totalStack - bin utils $KURL_BIN_UTILS_FILE - context $REPORTING_CONTEXT_INFO"

    if [ -n "$SUPPORT_BUNDLE_READY" ]; then
        collect_support_bundle
    fi

    exit 1
}

function stacktrace {
    local i=1
    local totalStack
    while caller $i > /dev/null; do
        read line func file <<<$(caller $i)
        totalStack="$totalStack (file: $file func: $func line: $line)"
        ((i++))
    done
    echo "$totalStack"
}

# attempt_get_cluster_id will get the cluster uuid from the kurl_cluster_uuid configmap and set the
# KURL_CLUSTER_UUID env var. If it does not exist or the cluster is down, check the disk to see if
# it is persisted there, otherwise make a new UUID for KURL_CLUSTER_UUID and save to disk.
function attempt_get_cluster_id() {
    if ! kubernetes_resource_exists kurl configmap kurl-cluster-uuid ; then
        # If the cluster is down, check to see if this is an etcd member and the cluster uuid is
        # persisted to disk.
        if [ -d /var/lib/etcd/member ] && [ -f /var/lib/kurl/clusteruuid ]; then
            KURL_CLUSTER_UUID=$(cat /var/lib/kurl/clusteruuid)
        else
            KURL_CLUSTER_UUID=$(< /dev/urandom tr -dc a-z0-9 | head -c32)
        fi
    else
        KURL_CLUSTER_UUID=$(kubectl get configmap -n kurl kurl-cluster-uuid -o jsonpath='{.data.kurl_cluster_uuid}')
    fi

    # Persist the cluster uuid to disk in case the cluster is down.
    # The tasks.sh reset command will remove the /var/lib/kurl directory and the cluster uuid will
    # be regenerated if reset.
    echo "$KURL_CLUSTER_UUID" > /var/lib/kurl/clusteruuid
}

# maybe_set_kurl_cluster_uuid will create the kurl_cluster_uuid configmap using the
# KURL_CLUSTER_UUID env var if it does not already exist.
function maybe_set_kurl_cluster_uuid() {
    if [ -z "$KURL_CLUSTER_UUID" ]; then
        return 0
    fi

    if kubernetes_resource_exists kurl configmap kurl-cluster-uuid; then
        return 0
    fi

    kubectl create configmap -n kurl kurl-cluster-uuid --from-literal=kurl_cluster_uuid="$KURL_CLUSTER_UUID"
}
