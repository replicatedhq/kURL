
function rook_pre_init() {
    local current_version='' current_version_minor='' current_version_patch=''
    local next_version_minor='' next_version_patch=''

    export SKIP_ROOK_INSTALL

    current_version="$(rook_version)"
    semverParse "${current_version}"
    current_version_major="${major}"
    current_version_minor="${minor}"
    current_version_patch="${patch}"

    semverParse "${ROOK_VERSION}"
    next_version_minor="${minor}"
    next_version_patch="${patch}"

    if [ -n "${current_version}" ]; then
        if [ "${current_version_minor}" != "${next_version_minor}" ]; then
            if [ "${current_version_minor}" -gt "${next_version_minor}" ]; then
                echo "Rook ${current_version} is already installed, will not downgrade to ${ROOK_VERSION}"
                SKIP_ROOK_INSTALL=1
            # upgrades from version 1.0.4 unsupported
            elif [ "${current_version_major}" = "1" ] && [ "${current_version_minor}" = "0" ]; then
                echo "Rook ${current_version} is already installed, will not upgrade to ${ROOK_VERSION}"
                SKIP_ROOK_INSTALL=1
                if [ "$KUBERNETES_TARGET_VERSION_MINOR" -ge 20 ]; then
                    KUBERNETES_UPGRADE="0"
                    KUBERNETES_VERSION=$(kubectl version --short | grep -i server | awk '{ print $3 }' | sed 's/^v*//')
                    parse_kubernetes_target_version
                    # There's no guarantee the packages from this version of Kubernetes are still available
                    SKIP_KUBERNETES_HOST=1
                fi
            fi
        elif [ "${current_version_patch}" -gt "${next_version_patch}" ]; then
            echo "Rook ${current_version} is already installed, will not downgrade to ${ROOK_VERSION}"
            SKIP_ROOK_INSTALL=1
        fi
    fi

    if [ "${ROOK_BYPASS_UPGRADE_WARNING}" != "1" ]; then
        if [ -z "${SKIP_ROOK_INSTALL}" ] && [ -n "${current_version}" ] && [ "${current_version}" != "${ROOK_VERSION}" ]; then
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

    rook_lvm2
}

function rook() {
    local src="${DIR}/addons/rook/${ROOK_VERSION}"

    if [ -n "$SKIP_ROOK_INSTALL" ]; then
        local version
        version=$(rook_version)
        echo "Rook $version is already installed, will not upgrade to ${ROOK_VERSION}"
        rook_object_store_output
        return 0
    fi

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
    local rook_major_minor_version="${major}.${minor}"

    printf "\n\n${GREEN}Rook Ceph 1.4+ requires a secondary, unformatted block device attached to the host.${NC}\n"
    printf "${GREEN}If you are stuck waiting at this step for more than two minutes, you are either missing the device or it is already formatted.${NC}\n"
    printf "\t${GREEN} * If it is missing, attach it now and it will be picked up; or CTRL+C, attach, and re-start the installer${NC}\n"
    printf "\t${GREEN} * If the disk is attached, try wiping it using the recommended zap procedure: https://rook.io/docs/rook/v${rook_major_minor_version}/ceph-teardown.html#zapping-devices${NC}\n\n"

    printf "checking for attached secondary block device (awaiting rook-ceph RGW pod)\n"
    spinnerPodRunning rook-ceph rook-ceph-rgw-rook-ceph-store
    kubectl -n rook-ceph apply -f "$src/cluster/object-user.yaml"
    rook_object_store_output

    echo "Awaiting rook-ceph object store health"
    if ! spinner_until 120 rook_rgw_is_healthy; then
        bail "Failed to detect healthy Rook RGW"
    fi

    # wait for all pods in the rook-ceph namespace to rollout
    log "Awaiting Rook rollout in rook-ceph namespace"
    rook_maybe_wait_for_rollout
}

function rook_join() {
    rook_lvm2
}

function rook_already_applied() {
    rook_object_store_output
    $DIR/bin/kurl rook wait-for-health 120
    rook_maybe_wait_for_rollout
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

    kubectl -n rook-ceph apply -k "$dst"
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
    render_yaml_file_2 "$src/patches/tmpl-rbd-storageclass.yaml" > "$dst/patches/rbd-storageclass.yaml"
    insert_patches_strategic_merge "$dst/kustomization.yaml" patches/rbd-storageclass.yaml
    if [ "$KUBERNETES_TARGET_VERSION_MINOR" -lt "17" ]; then
        sed -i 's/system-cluster-critical/rook-critical/g' "$dst/patches/cluster.yaml" "$dst/patches/object.yaml" "$dst/patches/filesystem.yaml"
    fi

    kubectl -n rook-ceph apply -k "$dst/"
}

function rook_cluster_deploy_upgrade() {
    local ceph_image="ceph/ceph:v15.2.9"
    local ceph_version=
    ceph_version="$(echo "${ceph_image}" | awk 'BEGIN { FS=":v" } ; {print $2}')"

    if rook_ceph_version_deployed "${ceph_version}" ; then
        echo "Cluster rook-ceph up to date"
        return 0
    fi

    echo "Awaiting rook-ceph operator"

    if ! spinner_until 1200 rook_version_deployed ; then
        logWarn "Timeout awaiting Rook version to be deployed"
        logStep "Checking Rook versions and replicas"
        kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{.metadata.name}{"  \treq/upd/avl: "}{.spec.replicas}{"/"}{.status.updatedReplicas}{"/"}{.status.readyReplicas}{"  \trook-version="}{.metadata.labels.rook-version}{"\n"}{end}'
        local rook_versions=
        rook_versions="$(kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"rook-version="}{.metadata.labels.rook-version}{"\n"}{end}' | sort | uniq)"
        if [ -n "${rook_versions}" ] && [ "$(echo "${rook_versions}" | wc -l)" -gt "1" ]; then
            logWarn "Detected multiple Rook versions"
            logWarn "${rook_versions}"
            logWarn "Failed to verify the Rook upgrade, multiple Rook versions detected"
        fi
    fi

    logStep "Upgrading rook-ceph cluster"

    if ! $DIR/bin/kurl rook wait-for-health 120 ; then
        kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
        bail "Refusing to update cluster rook-ceph, Ceph is not healthy"
    fi

    kubectl -n rook-ceph patch cephcluster/rook-ceph --type='json' -p='[{"op": "replace", "path": "/spec/cephVersion/image", "value":"'"${ceph_image}"'"}]'

    if ! spinner_until 1200 rook_ceph_version_deployed "${ceph_version}" ; then
        bail "New Ceph version failed to deploy"
    fi

    logSuccess "Rook-ceph cluster upgraded"
}

function rook_dashboard_ready_spinner() {
    # wait for ceph dashboard password to be generated
    echo "Awaiting rook-ceph dashboard password"
    local delay=0.75
    local spinstr='|/-\'
    while ! kubectl -n rook-ceph get secret rook-ceph-dashboard-password >/dev/null 2>&1 ; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
}

function rook_ready_spinner() {
    echo "Awaiting rook-ceph pods"

    spinnerPodRunning rook-ceph rook-ceph-operator
    spinnerPodRunning rook-ceph rook-discover
}

function rook_ceph_healthy() {
    local tools_pod=
    tools_pod="$(kubectl -n rook-ceph get pod -l "app=rook-ceph-tools" -o jsonpath='{.items[0].metadata.name}')"
    if kubectl -n rook-ceph exec "${tools_pod}" -- ceph status | grep -qE '(HEALTH_OK|HEALTH_WARN)' ; then
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

function rook_is_1() {
    kubectl -n rook-ceph get cephblockpools replicapool >/dev/null 2>&1
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

function rook_configure_linux_3() {
    if [ "$KERNEL_MAJOR" -eq "3" ]; then
        modprobe rbd
        echo 'rbd' > /etc/modules-load.d/replicated-rook.conf

        echo "net.bridge.bridge-nf-call-ip6tables = 1" > /etc/sysctl.d/k8s.conf
        echo "net.bridge.bridge-nf-call-iptables = 1" >> /etc/sysctl.d/k8s.conf
        echo "net.ipv4.conf.all.forwarding = 1" >> /etc/sysctl.d/k8s.conf

        sysctl --system
    fi
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
        --noproxy "*" \
        -H "Host: $OBJECT_STORE_CLUSTER_IP" \
        -H "Date: $d" \
        -H "$acl" \
        -H "Authorization: AWS $OBJECT_STORE_ACCESS_KEY:$sig" \
        "http://$OBJECT_STORE_CLUSTER_IP/$bucket" >/dev/null
}

function rook_rgw_is_healthy() {
    curl --noproxy "*" --fail --silent --insecure "http://${OBJECT_STORE_CLUSTER_IP}" > /dev/null
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

    if is_rhel_9_variant; then
        yum_ensure_host_package lvm2
    else
        install_host_archives "$src" lvm2
    fi
}


function rook_ceph_cluster_ready_spinner() {
    log "Awaiting CephCluster CR to report Ready"
    local delay="$1"
    local duration="$2"
    local ready_threshold=5
    local successful_ready_status_count=0
    local spinstr='|/-\'
    local start_time=
    local end_time=

    # defaults
    if [ -z "$delay" ]; then
        delay=5
    fi
    if [ -z "$duration" ]; then
        duration=300
    fi

    start_time=$(date +%s)
    end_time=$((start_time+duration))
    while [ "$(date +%s)" -lt $end_time ]
    do
        local temp=${spinstr#?}
        local spinstr=$temp${spinstr%"$temp"}
        local ceph_status_phase=
        local ceph_status_msg=
        ceph_status_phase=$(kubectl -n rook-ceph get cephcluster rook-ceph -o jsonpath='{.status.phase}')
        ceph_status_msg=$(kubectl -n rook-ceph get cephcluster rook-ceph -o jsonpath='{.status.message}')
        if [[ "$ceph_status_phase" == "Ready" ]]; then
            log "  Current CephCluster status is: $ceph_status_phase"
            successful_ready_status_count=$((successful_ready_status_count+1))
            if [ $successful_ready_status_count -eq $ready_threshold ]; then
                log "CephCluster is ready"
                return 0
            fi
        else
            log "  Current CephCluster status is $ceph_status_phase: $ceph_status_msg"
            successful_ready_status_count=0
        fi

        # simulate a spinner
        printf " [%c]  " "$spinstr"
        printf "\b\b\b\b\b\b"
        sleep "$delay"
    done
    logWarn "Rook CephCluster is not ready"
}


# wait for Rook deployment pods to be running/completed
function rook_maybe_wait_for_rollout() {
    # wait for Rook CephCluster CR to report Ready
    # probe set to 10s
    # timeout set to 300s (5mins)
    rook_ceph_cluster_ready_spinner 10 300

    log "Awaiting Rook pods to transition to Running"
    if ! spinner_until 120 check_for_running_pods "rook-ceph"; then
        logWarn "Rook-ceph rollout did not complete within the allotted time"
    fi
}
