CEPH_VERSION=15.2.4-20200819

function rook_pre_init() {
    local version=$(rook_version)
    if [ -n "$version" ] && [ "$version" != "1.4.3" ]; then
        printf "Rook $version is already installed, will not upgrade to 1.4.3\n"
        export SKIP_ROOK_INSTALL='true'
        if [ "$version" = "1.0.4" ] && [ "$KUBERNETES_TARGET_VERSION_MINOR" -ge 20 ]; then
            KUBERNETES_UPGRADE="0"
            KUBERNETES_VERSION=$(kubectl get nodes --sort-by='{.status.nodeInfo.kubeletVersion}' -o=jsonpath='{.items[0].status.nodeInfo.kubeletVersion}' | sed 's/^v*//')
            parse_kubernetes_target_version
            # There's no guarantee the packages from this version of Kubernetes are still available
            SKIP_KUBERNETES_HOST=1
        fi
    fi

    rook_lvm2
}

function rook() {
    if [ -n "$SKIP_ROOK_INSTALL" ]; then
        local version=$(rook_version)
        printf "Rook $version is already installed, will not upgrade to 1.4.3\n"
        rook_object_store_output
        return 0
    fi

    rook_operator_deploy
    rook_set_ceph_pool_replicas
    rook_ready_spinner # creating the cluster before the operator is ready fails
    rook_cluster_deploy

    rook_dashboard_ready_spinner
    CEPH_DASHBOARD_URL=http://rook-ceph-mgr-dashboard.rook-ceph.svc.cluster.local:7000
    # Ceph v13+ requires login. Rook 1.0+ creates a secret in the rook-ceph namespace.
    local cephDashboardPassword=$(kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode)
    if [ -n "$cephDashboardPassword" ]; then
        CEPH_DASHBOARD_USER=admin
        CEPH_DASHBOARD_PASSWORD="$cephDashboardPassword"
    fi

    semverParse "$ROOK_VERSION"
    local rook_major_minor_version="${major}.${minor}"

    printf "\n\n${GREEN}Rook Ceph 1.4+ requires a secondary, unformatted block device attached to the host.${NC}\n"
    printf "${GREEN}If you are stuck waiting at this step for more than two minutes, you are either missing the device or it is already formatted.${NC}\n"
    printf "\t${GREEN} * If it is missing, attach it now and it will be picked up; or CTRL+C, attach, and re-start the installer${NC}\n"
    printf "\t${GREEN} * If the disk is attached, try wiping it using the recommended zap procedure: https://rook.io/docs/rook/v${rook_major_minor_version}/ceph-teardown.html#zapping-devices${NC}\n\n"

    printf "checking for attached secondary block device (awaiting rook-ceph RGW pod)\n"
    spinnerPodRunning rook-ceph rook-ceph-rgw-rook-ceph-store
    kubectl apply -f "$DIR/addons/rook/1.4.3/cluster/object-user.yaml"
    rook_object_store_output

    printf "awaiting rook-ceph object store health\n"
    if ! spinner_until 120 rook_rgw_is_healthy; then
        bail "Failed to detect healthy Rook RGW"
    fi
}

function rook_join() {
    rook_lvm2
}

function rook_already_applied() {
    rook_object_store_output
}

function rook_operator_deploy() {
    local src="$DIR/addons/rook/1.4.3/operator"
    local dst="$DIR/kustomize/rook/operator"

    cp -r "$src" "$dst"

    if [ "${K8S_DISTRO}" = "rke2" ]; then
        ROOK_HOSTPATH_REQUIRES_PRIVILEGED=1
        cp "$src/patches/ceph-operator-rke2.yaml" "$dst/"
        insert_patches_strategic_merge "$dst/kustomization.yaml" ceph-operator-rke2.yaml
    fi

    if [ "$ROOK_HOSTPATH_REQUIRES_PRIVILEGED" = "1" ]; then
        cp "$src/patches/ceph-operator-privileged.yaml" "$dst/"
        insert_patches_strategic_merge "$dst/kustomization.yaml" ceph-operator-privileged.yaml
    fi

    kubectl apply -k "$dst/"
}

function rook_cluster_deploy() {
    local src="$DIR/addons/rook/1.4.3/cluster"
    local dst="$DIR/kustomize/rook/cluster"

    # Don't redeploy cluster - ekco may have made changes based on num of nodes in cluster
    if kubectl -n rook-ceph get cephcluster rook-ceph 2>/dev/null 1>/dev/null; then
        echo "Cluster rook-ceph already deployed"
        return 0
    fi

    mkdir -p "$dst"
    cp "$src/kustomization.yaml" "$dst/"

    # resources
    cp "$src/ceph-cluster.yaml" "$dst/"
    cp "$src/ceph-block-pool.yaml" "$dst/"
    cp "$src/ceph-object-store.yaml" "$dst/"
    render_yaml_file "$src/tmpl-ceph-storage-class.yaml" > "$dst/ceph-storage-class.yaml"

    # conditional cephfs
    if [ "${ROOK_SHARED_FILESYSTEM_DISABLED}" != "1" ]; then
        cp "$src/shared-fs.yaml" "$dst/"
        insert_resources "$dst/kustomization.yaml" shared-fs.yaml
    fi

    # patches
    cp "$src/patches/ceph-cluster-mons.yaml" "$dst/"
    cp "$src/patches/ceph-cluster-tolerate.yaml" "$dst/"
    render_yaml_file "$src/patches/tmpl-ceph-cluster-image.yaml" > "$dst/ceph-cluster-image.yaml"
    render_yaml_file "$src/patches/tmpl-ceph-block-pool-replicas.yaml" > "$dst/ceph-block-pool-replicas.yaml"
    render_yaml_file "$src/patches/tmpl-ceph-object-store.yaml" > "$dst/ceph-object-store-replicas.yaml"
    render_yaml_file "$src/patches/tmpl-ceph-cluster-block-storage.yaml" > "$dst/ceph-cluster-storage.yaml"

    kubectl apply -k "$dst/"
}

function rook_dashboard_ready_spinner() {
    # wait for ceph dashboard password to be generated
    printf "awaiting rook-ceph dashboard password\n"
    local delay=0.75
    local spinstr='|/-\'
    while ! kubectl -n rook-ceph get secret rook-ceph-dashboard-password &>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
}

function rook_ready_spinner() {
    printf "awaiting rook-ceph pods\n"
    spinnerPodRunning rook-ceph rook-ceph-operator
    spinnerPodRunning rook-ceph rook-discover
}

function rook_is_1() {
    kubectl -n rook-ceph get cephblockpools replicapool &>/dev/null
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
    local discoveredCephPoolReplicas=$(kubectl -n rook-ceph get cephblockpool replicapool -o jsonpath="{.spec.replicated.size}" 2>/dev/null)
    if [ -n "$discoveredCephPoolReplicas" ]; then
        CEPH_POOL_REPLICAS="$discoveredCephPoolReplicas"
    fi
    local readyNodeCount=$(kubectl get nodes 2>/dev/null | grep ' Ready' | wc -l)
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
    while ! kubectl -n rook-ceph get secret rook-ceph-object-user-rook-ceph-store-kurl 2>/dev/null; do
        sleep 2
    done

    # create the docker-registry bucket through the S3 API
    OBJECT_STORE_ACCESS_KEY=$(kubectl -n rook-ceph get secret rook-ceph-object-user-rook-ceph-store-kurl -o yaml | grep AccessKey | head -1 | awk '{print $2}' | base64 --decode)
    OBJECT_STORE_SECRET_KEY=$(kubectl -n rook-ceph get secret rook-ceph-object-user-rook-ceph-store-kurl -o yaml | grep SecretKey | head -1 | awk '{print $2}' | base64 --decode)
    OBJECT_STORE_CLUSTER_IP=$(kubectl -n rook-ceph get service rook-ceph-rgw-rook-ceph-store | tail -n1 | awk '{ print $3}')
    OBJECT_STORE_CLUSTER_HOST="http://rook-ceph-rgw-rook-ceph-store.rook-ceph"
}

# deprecated, use object_store_create_bucket
function rook_create_bucket() {
    local bucket=$1
    local acl="x-amz-acl:private"
    local d=$(LC_TIME="en_US.UTF-8" TZ="UTC" date +"%a, %d %b %Y %T %z")
    local string="PUT\n\n\n${d}\n${acl}\n/$bucket"
    local sig=$(echo -en "${string}" | openssl dgst -sha1 -hmac "${OBJECT_STORE_SECRET_KEY}" -binary | base64)

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
    local src="$DIR/addons/rook/$ROOK_VERSION"
    if commandExists lvm; then
        return
    fi

    if ! host_packages_shipped ; then
        ensure_host_package lvm2 lvm2
    else
        install_host_archives "$src" lvm2
    fi
}
