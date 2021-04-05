
function rook_pre_init() {
    local version
    version=$(rook_version)
    if [ -n "$version" ] && [ "$version" != "${ROOK_VERSION}" ]; then
        echo "Rook $version is already installed, will not upgrade to ${ROOK_VERSION}"
        export SKIP_ROOK_INSTALL='true'
    elif [ "$ROOK_BLOCK_STORAGE_ENABLED" != "1" ]; then
        bail "Rook ${ROOK_VERSION} requires enabling block storage"
    fi
}

function rook() {
    local src="${DIR}/addons/rook/${ROOK_VERSION}"

    rook_lvm2

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

    echo "awaiting rook-ceph RGW pod"
    spinnerPodRunning rook-ceph rook-ceph-rgw-rook-ceph-store
    kubectl apply -f "$src/cluster/object-user.yaml"
    rook_object_store_output

    echo "awaiting rook-ceph object store health"
    if ! spinner_until 120 rook_rgw_is_healthy; then
        bail "Failed to detect healthy Rook RGW"
    fi
}

function rook_join() {
    rook_lvm2
}

function rook_operator_deploy() {
    local src="${DIR}/addons/rook/${ROOK_VERSION}/operator"
    local dst="${DIR}/kustomize/rook/operator"

    mkdir -p "$dst"
    # resources
    cp "$src/*" "$dst/"

    if [ "${K8S_DISTRO}" = "rke2" ]; then
        ROOK_HOSTPATH_REQUIRES_PRIVILEGED=1
        cp "$src/patches/ceph-operator-rke2.yaml" "$dst"
        insert_patches_strategic_merge "$dst/kustomization.yaml" ceph-operator-rke2.yaml
    fi

    if [ "$ROOK_HOSTPATH_REQUIRES_PRIVILEGED" = "1" ]; then
        cp "$src/patches/ceph-operator-privileged.yaml" "$dst"
        insert_patches_strategic_merge "$dst/kustomization.yaml" ceph-operator-privileged.yaml
    fi

    kubectl apply -k "$dst"
}

function rook_cluster_deploy() {
    local src="${DIR}/addons/rook/${ROOK_VERSION}/cluster"
    local dst="${DIR}/kustomize/rook/cluster"

    # Don't redeploy cluster - ekco may have made changes based on num of nodes in cluster
    if kubectl -n rook-ceph get cephcluster rook-ceph 2>/dev/null 1>/dev/null; then
        echo "Cluster rook-ceph already deployed"
        return 0
    fi

    mkdir -p "$dst"
    # resources
    cp "$src/*" "$dst/"
    render_yaml_file "$src/tmpl-rdb-storageclass.yaml" > "$dst/rdb-storageclass.yaml"

    # patches
    # TODO (ethan)
    render_yaml_file "$src/patches/tmpl-ceph-cluster-image.yaml" > "$dst/ceph-cluster-image.yaml"
    render_yaml_file "$src/patches/tmpl-ceph-block-pool-replicas.yaml" > "$dst/ceph-block-pool-replicas.yaml"
    render_yaml_file "$src/patches/tmpl-ceph-object-store.yaml" > "$dst/ceph-object-store-replicas.yaml"
    render_yaml_file "$src/patches/tmpl-ceph-cluster-block-storage.yaml" > "$dst/ceph-cluster-storage.yaml"

    kubectl apply -k "$dst/"
}

function rook_dashboard_ready_spinner() {
    # wait for ceph dashboard password to be generated
    echo "awaiting rook-ceph dashboard password"
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
    echo "awaiting rook-ceph pods"
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
    local discoveredCephPoolReplicas
    discoveredCephPoolReplicas=$(kubectl -n rook-ceph get cephblockpool replicapool -o jsonpath="{.spec.replicated.size}" 2>/dev/null)
    if [ -n "$discoveredCephPoolReplicas" ]; then
        CEPH_POOL_REPLICAS="$discoveredCephPoolReplicas"
    fi
    local readyNodeCount
    readyNodeCount=$(kubectl get nodes 2>/dev/null | grep -c Ready)
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
    echo "Installing lvm"

    install_host_archives "$src"
}
