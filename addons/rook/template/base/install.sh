
function rook_pre_init() {
    local current_version="$(rook_version)"

    export SKIP_ROOK_INSTALL
    if rook_should_skip_rook_install "$current_version" "$ROOK_VERSION" ; then
        SKIP_ROOK_INSTALL=1

        if [ "$KUBERNETES_TARGET_VERSION_MINOR" -ge 20 ] && [ "$current_version" = "1.0.4" ]; then
            KUBERNETES_UPGRADE="0"
            KUBERNETES_VERSION=$(kubectl version --short | grep -i server | awk '{ print $3 }' | sed 's/^v*//')
            parse_kubernetes_target_version
            # There's no guarantee the packages from this version of Kubernetes are still available
            SKIP_KUBERNETES_HOST=1
        fi
    fi

    if [ "${ROOK_BYPASS_UPGRADE_WARNING}" != "1" ]; then
        if [ "$SKIP_ROOK_INSTALL" != "1" ] && [ -n "$current_version" ] && [ "$current_version" != "$ROOK_VERSION" ]; then
            logWarn "WARNING: This installer will upgrade Rook to version ${ROOK_VERSION}."
            logWarn "Upgrading a Rook cluster is not without risk, including data loss."
            logWarn "The Rook cluster's storage may be unavailable for short periods during the upgrade process."
            log ""
            log "Would you like to continue? "
            if ! confirmN ; then
                logWarn "Will not upgrade rook-ceph cluster"
                SKIP_ROOK_INSTALL=1
            fi
        fi
    fi
}

function rook() {
    local src="${DIR}/addons/rook/${ROOK_VERSION}"

    rook_lvm2

    if [ "$SKIP_ROOK_INSTALL" = "1" ]; then
        local version
        version=$(rook_version)
        echo "Rook $version is already installed, will not upgrade to ${ROOK_VERSION}"
        rook_object_store_output
        return 0
    fi

    rook_operator_crds_deploy
    rook_operator_deploy
    rook_set_ceph_pool_replicas
    rook_ready_spinner # creating the cluster before the operator is ready fails
    rook_cluster_deploy

    rook_dashboard_ready_spinner
    export CEPH_DASHBOARD_URL=http://rook-ceph-mgr-dashboard.rook-ceph.svc.cluster.local:7000
    # Ceph v13+ requires login. Rook 1.0+ creates a secret in the rook-ceph namespace.
    local cephDashboardPassword
    cephDashboardPassword=$(kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode)
    if [ -n "$cephDashboardPassword" ]; then
        export CEPH_DASHBOARD_USER=admin
        export CEPH_DASHBOARD_PASSWORD="$cephDashboardPassword"
    fi

    semverParse "$ROOK_VERSION"
    local rook_major_minior_version="${major}.${minor}"

    printf "\n\n${GREEN}Rook Ceph 1.4+ requires a secondary, unformatted block device attached to the host.${NC}\n"
    printf "${GREEN}If you are stuck waiting at this step for more than two minutes, you are either missing the device or it is already formatted.${NC}\n"
    printf "\t${GREEN} * If it is missing, attach it now and it will be picked up; or CTRL+C, attach, and re-start the installer${NC}\n"
    printf "\t${GREEN} * If the disk is attached, try wiping it using the recommended zap procedure: https://rook.io/docs/rook/v${rook_major_minior_version}/ceph-teardown.html#zapping-devices${NC}\n\n"

    printf "checking for attached secondary block device (awaiting rook-ceph RGW pod)\n"
    spinnerPodRunning rook-ceph rook-ceph-rgw-rook-ceph-store
    kubectl -n rook-ceph apply -f "$src/cluster/object-user.yaml"
    rook_object_store_output

    echo "Awaiting rook-ceph object store health"
    if ! spinner_until 120 rook_rgw_is_healthy ; then
        bail "Failed to detect healthy rook-ceph object store"
    fi
}

function rook_join() {
    rook_lvm2
}

function rook_already_applied() {
    rook_object_store_output
}

function rook_operator_crds_deploy() {
    local src="${DIR}/addons/rook/${ROOK_VERSION}"
    local dst="${DIR}/kustomize/rook"

    mkdir -p "${dst}"
    cp "$src/crds.yaml" "$dst/crds.yaml"

    # https://rook.io/docs/rook/v1.6/ceph-upgrade.html#1-update-common-resources-and-crds
    # NOTE: If your Rook-Ceph cluster was initially installed with rook v1.4 or lower, the above
    # command will return errors due to updates from Kubernetes’ v1beta1 Custom Resource
    # Definitions. The error will contain text similar to ... spec.preserveUnknownFields: Invalid
    # value....
    if ! kubectl apply -f "$dst/crds.yaml" ; then
        kubectl replace -f "$dst/crds.yaml"
        kubectl apply -f "$dst/crds.yaml"
    fi
}

function rook_operator_deploy() {
    local src="${DIR}/addons/rook/${ROOK_VERSION}/operator"
    local dst="${DIR}/kustomize/rook/operator"

    mkdir -p "${DIR}/kustomize/rook"
    rm -rf "$dst"
    cp -r "$src" "$dst"

    if [ "${K8S_DISTRO}" = "rke2" ]; then
        ROOK_HOSTPATH_REQUIRES_PRIVILEGED=1
        insert_patches_strategic_merge "$dst/kustomization.yaml" patches/deployment-rke2.yaml
    fi

    if [ "$ROOK_HOSTPATH_REQUIRES_PRIVILEGED" = "1" ]; then
        insert_patches_strategic_merge "$dst/kustomization.yaml" patches/deployment-privileged.yaml
    fi

    if [ "$KUBERNETES_TARGET_VERSION_MINOR" -lt "17" ]; then
        insert_resources "$dst/kustomization.yaml" priority-class.yaml
        insert_patches_strategic_merge "$dst/kustomization.yaml" patches/deployment-priority-class-16.yaml
    else
        insert_patches_strategic_merge "$dst/kustomization.yaml" patches/deployment-priority-class.yaml
    fi

    if [ "$IPV6_ONLY" = "1" ]; then
        sed -i "/\[global\].*/a\    ms bind ipv6 = true" "$dst/configmap-rook-config-override.yaml"
        sed -i "/\[global\].*/a\    ms bind ipv4 = false" "$dst/configmap-rook-config-override.yaml"
    fi

    # upgrade first before applying auth_allow_insecure_global_id_reclaim policy
    rook_maybe_auth_allow_insecure_global_id_reclaim

    kubectl -n rook-ceph apply -k "$dst/"
}

function rook_cluster_deploy() {
    local src="${DIR}/addons/rook/${ROOK_VERSION}/cluster"
    local dst="${DIR}/kustomize/rook/cluster"

    # Don't redeploy cluster - ekco may have made changes based on num of nodes in cluster
    if kubectl -n rook-ceph get cephcluster rook-ceph >/dev/null 2>&1 ; then
        echo "Cluster rook-ceph already deployed"
        rook_cluster_deploy_upgrade
        return 0
    fi

    mkdir -p "${DIR}/kustomize/rook"
    rm -rf "$dst"
    cp -r "$src" "$dst"

    # resources
    render_yaml_file_2 "$dst/tmpl-rbd-storageclass.yaml" > "$dst/rbd-storageclass.yaml"
    insert_resources "$dst/kustomization.yaml" rbd-storageclass.yaml

    # conditional cephfs
    if [ "${ROOK_SHARED_FILESYSTEM_DISABLED}" != "1" ]; then
        insert_resources "$dst/kustomization.yaml" cephfs-storageclass.yaml
        insert_resources "$dst/kustomization.yaml" filesystem.yaml
        insert_patches_strategic_merge "$dst/kustomization.yaml" patches/cephfs-storageclass.yaml
        insert_patches_strategic_merge "$dst/kustomization.yaml" patches/filesystem.yaml
        insert_patches_json_6902 "$dst/kustomization.yaml" patches/filesystem-Json6902.yaml ceph.rook.io v1 CephFilesystem myfs rook-ceph
    fi

    # patches
    render_yaml_file "$src/patches/tmpl-cluster.yaml" > "$dst/patches/cluster.yaml"
    insert_patches_strategic_merge "$dst/kustomization.yaml" patches/cluster.yaml
    render_yaml_file "$src/patches/tmpl-object.yaml" > "$dst/patches/object.yaml"
    insert_patches_strategic_merge "$dst/kustomization.yaml" patches/object.yaml
    render_yaml_file "$src/patches/tmpl-rbd-storageclass.yaml" > "$dst/patches/rbd-storageclass.yaml"
    insert_patches_strategic_merge "$dst/kustomization.yaml" patches/rbd-storageclass.yaml
    if [ "$KUBERNETES_TARGET_VERSION_MINOR" -lt "17" ]; then
        sed -i 's/system-cluster-critical/rook-critical/g' "$dst/patches/cluster.yaml" "$dst/patches/object.yaml" "$dst/patches/filesystem.yaml"
    fi

    kubectl -n rook-ceph apply -k "$dst/"
}

function rook_cluster_deploy_upgrade() {
    # Prior to calling this function the following steps have been taken in the upgrade process:
    # 1. https://rook.io/docs/rook/v1.6/ceph-upgrade.html#1-update-common-resources-and-crds
    #    rook_operator_crds_deploy
    #    rook_operator_deploy
    # 2. https://rook.io/docs/rook/v1.5/ceph-upgrade.html#2-update-ceph-csi-versions
    #    Not needed, using default CSI images
    # 3. https://rook.io/docs/rook/v1.6/ceph-upgrade.html#3-update-the-rook-operator
    #    rook_operator_deploy

    local ceph_image="__CEPH_IMAGE__"
    local ceph_version=
    ceph_version="$(echo "${ceph_image}" | awk 'BEGIN { FS=":v" } ; {print $2}')"

    if rook_ceph_version_deployed "${ceph_version}" ; then
        echo "Cluster rook-ceph up to date"
        rook_patch_insecure_clients
        return 0
    fi

    # 4. https://rook.io/docs/rook/v1.6/ceph-upgrade.html#4-wait-for-the-upgrade-to-complete
    echo "Awaiting rook-ceph operator"

    if ! spinner_until 600 rook_version_deployed ; then
        local rook_versions=
        rook_versions="$(kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"rook-version="}{.metadata.labels.rook-version}{"\n"}{end}' | sort | uniq)"
        if [ -n "${rook_versions}" ] && [ "$(echo "${rook_versions}" | wc -l)" -gt "1" ]; then
            logWarn "Detected multiple Rook versions"
            logWarn "${rook_versions}"
        fi
    fi

    # 5. https://rook.io/docs/rook/v1.6/ceph-upgrade.html#5-verify-the-updated-cluster
    echo "Awaiting Ceph healthy"

    # CRD changes makes rook to restart and it takes time to reconcile
    if ! spinner_until 600 rook_ceph_healthy ; then
        kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
        bail "Refusing to update cluster rook-ceph, Ceph is not healthy"
    fi

    # https://rook.io/docs/rook/v1.6/ceph-upgrade.html#ceph-version-upgrades
    logStep "Upgrading rook-ceph cluster"

    # https://rook.io/docs/rook/v1.6/ceph-upgrade.html#1-update-the-main-ceph-daemons

    kubectl -n rook-ceph patch cephcluster/rook-ceph --type='json' -p='[{"op": "replace", "path": "/spec/cephVersion/image", "value":"'"${ceph_image}"'"}]'

    # https://rook.io/docs/rook/v1.6/ceph-upgrade.html#2-wait-for-the-daemon-pod-updates-to-complete

    if ! spinner_until 600 rook_ceph_version_deployed "${ceph_version}" ; then
        bail "New Ceph version failed to deploy"
    fi

    # https://rook.io/docs/rook/v1.6/ceph-upgrade.html#3-verify-the-updated-cluster

    echo "Awaiting Ceph healthy"

    if ! spinner_until 300 rook_ceph_healthy ; then
        kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
        bail "Failed to verify the updated cluster, Ceph is not healthy"
    fi

    rook_patch_insecure_clients

    logSuccess "Rook-ceph cluster upgraded"
}

function rook_dashboard_ready_spinner() {
    echo "Awaiting rook-ceph dashboard password"

    spinner_until 300 kubernetes_resource_exists rook-ceph secret rook-ceph-dashboard-password
}

function rook_ready_spinner() {
    echo "Awaiting rook-ceph pods"

    spinner_until 60 kubernetes_resource_exists rook-ceph deployment rook-ceph-operator
    spinner_until 60 kubernetes_resource_exists rook-ceph daemonset rook-discover
    spinner_until 300 deployment_fully_updated rook-ceph rook-ceph-operator
    spinner_until 60 daemonset_fully_updated rook-ceph rook-discover
}

function rook_ceph_healthy() {
    if kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status | grep -qE '(HEALTH_OK|HEALTH_WARN)' ; then
        return 0
    fi
    return 1
}

# rook_version_deployed check that there is only one rook-version reported across the cluster
function rook_version_deployed() {
    # wait for our version to start reporting
    if ! kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"rook-version="}{.metadata.labels.rook-version}{"\n"}{end}' | grep -q "${ROOK_VERSION}" ; then
        return 1
    fi
    # wait for our version to be the only one reporting
    if [ "$(kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"rook-version="}{.metadata.labels.rook-version}{"\n"}{end}' | sort | uniq | wc -l)" != "1" ]; then
        return 1
    fi
    # sanity check
    if ! kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"rook-version="}{.metadata.labels.rook-version}{"\n"}{end}' | grep -q "${ROOK_VERSION}" ; then
        return 1
    fi
    return 0
}

# rook_ceph_version_deployed check that there is only one ceph-version reported across the cluster
function rook_ceph_version_deployed() {
    local ceph_version="$1"
    # wait for our version to start reporting
    if ! kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"ceph-version="}{.metadata.labels.ceph-version}{"\n"}{end}' | grep -q "${ceph_version}" ; then
        return 1
    fi
    # wait for our version to be the only one reporting
    if [ "$(kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"ceph-version="}{.metadata.labels.ceph-version}{"\n"}{end}' | sort | uniq | wc -l)" != "1" ]; then
        return 1
    fi
    # sanity check
    if ! kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"ceph-version="}{.metadata.labels.ceph-version}{"\n"}{end}' | grep -q "${ceph_version}" ; then
        return 1
    fi
    return 0
}

# CEPH_POOL_REPLICAS is undefined when this function is called unless set explicitly with a flag.
# If set by flag use that value.
# Else if the replicapool cephbockpool CR in the rook-ceph namespace is found, set CEPH_POOL_REPLICAS to that.
# Then increase up to 3 based on the number of ready nodes found.
# The ceph-pool-replicas flag will override any value set here.
function rook_set_ceph_pool_replicas() {
    if [ -n "$CEPH_POOL_REPLICAS" ]; then
        return 0
    fi
    CEPH_POOL_REPLICAS=1
    set +e
    local discoveredCephPoolReplicas
    discoveredCephPoolReplicas=$(kubectl -n rook-ceph get cephblockpool replicapool -o jsonpath="{.spec.replicated.size}" 2>/dev/null)
    if [ -n "$discoveredCephPoolReplicas" ]; then
        CEPH_POOL_REPLICAS="$discoveredCephPoolReplicas"
    fi
    local readyNodeCount
    readyNodeCount=$(kubectl get nodes 2>/dev/null | grep -c ' Ready')
    if [ "$readyNodeCount" -gt "$CEPH_POOL_REPLICAS" ] && [ "$readyNodeCount" -le "3" ]; then
        CEPH_POOL_REPLICAS="$readyNodeCount"
    fi
    set -e
}

function rook_object_store_output() {
    # Rook operator creates this secret from the user CRD just applied
    while ! kubectl -n rook-ceph get secret rook-ceph-object-user-rook-ceph-store-kurl >/dev/null 2>&1 ; do
        sleep 2
    done

    # create the docker-registry bucket through the S3 API
    export OBJECT_STORE_ACCESS_KEY
    OBJECT_STORE_ACCESS_KEY=$(kubectl -n rook-ceph get secret rook-ceph-object-user-rook-ceph-store-kurl -o yaml | grep AccessKey | head -1 | awk '{print $2}' | base64 --decode)
    export OBJECT_STORE_SECRET_KEY
    OBJECT_STORE_SECRET_KEY=$(kubectl -n rook-ceph get secret rook-ceph-object-user-rook-ceph-store-kurl -o yaml | grep SecretKey | head -1 | awk '{print $2}' | base64 --decode)
    export OBJECT_STORE_CLUSTER_IP
    OBJECT_STORE_CLUSTER_IP=$(kubectl -n rook-ceph get service rook-ceph-rgw-rook-ceph-store | tail -n1 | awk '{ print $3}')
    export OBJECT_STORE_CLUSTER_HOST="http://rook-ceph-rgw-rook-ceph-store.rook-ceph"
    # same as OBJECT_STORE_CLUSTER_IP for IPv4, wrapped in brackets for IPv6
    export OBJECT_STORE_CLUSTER_IP_BRACKETED=$($DIR/bin/kurl format-address "$OBJECT_STORE_CLUSTER_IP")
}

# deprecated, use object_store_create_bucket
function rook_create_bucket() {
    local bucket=$1
    local acl="x-amz-acl:private"
    local d
    d=$(LC_TIME="en_US.UTF-8" TZ="UTC" date +"%a, %d %b %Y %T %z")
    local string="PUT\n\n\n${d}\n${acl}\n/${bucket}"
    local sig
    sig=$(echo -en "${string}" | openssl sha1 -hmac "${OBJECT_STORE_SECRET_KEY}" -binary | base64)

    curl -X PUT  \
        --globoff \
        --noproxy "*" \
        -H "Host: $OBJECT_STORE_CLUSTER_IP" \
        -H "Date: $d" \
        -H "$acl" \
        -H "Authorization: AWS $OBJECT_STORE_ACCESS_KEY:$sig" \
        "http://$OBJECT_STORE_CLUSTER_IP_BRACKETED/$bucket" >/dev/null
}

function rook_rgw_is_healthy() {
    curl --globoff --noproxy "*" --fail --silent --insecure "http://${OBJECT_STORE_CLUSTER_IP_BRACKETED}" > /dev/null
}

function rook_version() {
    kubectl -n rook-ceph get deploy rook-ceph-operator -oyaml 2>/dev/null \
        | grep ' image: ' \
        | awk -F':' 'NR==1 { print $3 }' \
        | sed 's/v\([^-]*\).*/\1/'
}

function rook_lvm2() {
    local src="${DIR}/addons/rook/${ROOK_VERSION}"
    if commandExists lvm; then
        return
    fi

    install_host_archives "$src" lvm2
}

function rook_patch_insecure_clients {
    echo "Patching allowance of insecure rook clients"

    # upgrade first before applying auth_allow_insecure_global_id_reclaim policy
    if ! kubectl -n rook-ceph get configmap rook-config-override -ojsonpath='{.data.config}' | grep -q 'auth_allow_insecure_global_id_reclaim = true' ; then
        local dst="${DIR}/kustomize/rook/operator"
        sed -i 's/auth_allow_insecure_global_id_reclaim = true/auth_allow_insecure_global_id_reclaim = false/' "$dst/configmap-rook-config-override.yaml"
        kubectl -n rook-ceph apply -f "$dst/configmap-rook-config-override.yaml"
    fi

    # Disabling rook global_id reclaim
    kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph config set mon auth_allow_insecure_global_id_reclaim false

    # Checking to ensure ceph status
    if ! spinner_until 120 rook_clients_secure; then
        logWarn "Mon is still allowing insecure clients"
    fi
}

function rook_clients_secure {
    if kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail | grep -q AUTH_INSECURE_GLOBAL_ID_RECLAIM ; then
        return 1
    fi
    return 0
}

# do not downgrade rook or upgrade more than one minor version at a time
function rook_should_skip_rook_install() {
    local current_version="$1"
    local next_version="$2"

    local current_version_minor='' current_version_patch=''
    local next_version_minor='' next_version_patch=''

    semverParse "${current_version}"
    current_version_minor="${minor}"
    current_version_patch="${patch}"

    semverParse "${next_version}"
    next_version_minor="${minor}"
    next_version_patch="${patch}"

    if [ -n "${current_version}" ]; then
        if [ "${current_version_minor}" != "${next_version_minor}" ]; then
            if [ "${current_version_minor}" -gt "${next_version_minor}" ]; then
                echo "Rook ${current_version} is already installed, will not downgrade to ${next_version}"
                return 0
            # only upgrades from prior minor versions supported
            elif [ "${current_version_minor}" -lt "$((next_version_minor-1))" ]; then
                echo "Rook ${current_version} is already installed, will not upgrade to ${next_version}"
                return 0
            fi
        elif [ "${current_version_patch}" -gt "${next_version_patch}" ]; then
            echo "Rook ${current_version} is already installed, will not downgrade to ${next_version}"
            return 0
        fi
    fi
    return 1
}

# TODO: move this to common
# this waits for a daemonset to have all replicas up-to-date and available
function daemonset_fully_updated() {
    local namespace=$1
    local daemonset=$2

    local desiredNumberScheduled
    desiredNumberScheduled=$(kubectl get daemonset -n "$namespace" "$daemonset" -o jsonpath='{.status.desiredNumberScheduled}')

    local currentNumberScheduled
    currentNumberScheduled=$(kubectl get daemonset -n "$namespace" "$daemonset" -o jsonpath='{.status.currentNumberScheduled}')

    local numberAvailable
    numberAvailable=$(kubectl get daemonset -n "$namespace" "$daemonset" -o jsonpath='{.status.numberAvailable}')

    local numberReady
    numberReady=$(kubectl get daemonset -n "$namespace" "$daemonset" -o jsonpath='{.status.numberReady}')

    local updatedNumberScheduled
    updatedNumberScheduled=$(kubectl get daemonset -n "$namespace" "$daemonset" -o jsonpath='{.status.updatedNumberScheduled}')

    if [ "$desiredNumberScheduled" != "$numberAvailable" ] ; then
        return 1
    fi

    if [ "$desiredNumberScheduled" != "$currentNumberScheduled" ] ; then
        return 1
    fi

    if [ "$desiredNumberScheduled" != "$numberAvailable" ] ; then
        return 1
    fi

    if [ "$desiredNumberScheduled" != "$numberReady" ] ; then
        return 1
    fi

    if [ "$desiredNumberScheduled" != "$updatedNumberScheduled" ] ; then
        return 1
    fi

    return 0
}

function rook_maybe_auth_allow_insecure_global_id_reclaim() {
    local dst="${DIR}/kustomize/rook/operator"

    local ceph_version="$(rook_detect_ceph_version)"
    if rook_should_auth_allow_insecure_global_id_reclaim "$ceph_version" ; then
        sed -i 's/auth_allow_insecure_global_id_reclaim = false/auth_allow_insecure_global_id_reclaim = true/' "$dst/configmap-rook-config-override.yaml"
        return
    fi
}

function rook_should_auth_allow_insecure_global_id_reclaim() {
    local ceph_version="$1"

    if [ -z "$ceph_version" ]; then
        # rook ceph not deployed, allow since not upgrading
        return 0
    fi

    # https://docs.ceph.com/en/latest/security/CVE-2021-20288/
    semverParse "$ceph_version"
    local ceph_version_major="$major"
    local ceph_version_minor="$minor"
    local ceph_version_patch="$patch"

    case "$ceph_version_major" in
    # Pacific v16.2.1 (and later)
    "16")
        if [ "$ceph_version_patch" -lt "1" ]; then
            return 0
        fi
        ;;
    # Octopus v15.2.11 (and later)
    "15")
        if [ "$ceph_version_patch" -lt "11" ]; then
            return 0
        fi
        ;;
    # Nautilus v14.2.20 (and later)
    "14")
        if [ "$ceph_version_patch" -lt "20" ]; then
            return 0
        fi
        ;;
    esac

    return 1
}

function rook_detect_ceph_version() {
    kubectl -n rook-ceph get deployment rook-ceph-mgr-a -o jsonpath='{.metadata.labels.ceph-version}' 2>/dev/null | awk -F'-' '{ print $1 }'
}
