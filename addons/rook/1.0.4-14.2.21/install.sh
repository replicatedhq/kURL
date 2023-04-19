

# Just to test it out

function rook_pre_init() {
    if [ "$KUBERNETES_TARGET_VERSION_MINOR" -ge 20 ]; then
        bail "Rook ${ROOK_VERSION} is not compatible with Kubernetes 1.20+"
    fi

    rook_lvm2
}

function rook() {
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

    printf "awaiting rook-ceph RGW pod\n"
    spinnerPodRunning rook-ceph rook-ceph-rgw-rook-ceph-store
    kubectl apply -f "$DIR/addons/rook/${ROOK_VERSION}/cluster/object-user.yaml"
    rook_object_store_output

    printf "awaiting rook-ceph object store health\n"
    if ! spinner_until 120 rook_rgw_is_healthy; then
        bail "Failed to detect healthy Rook RGW"
    fi


    if ! spinner_until 1200 rook_ceph_version_deployed; then
        rook_ceph_edit_version
    fi

    rook_patch_insecure_clients
}

function rook_operator_deploy() {
    local src="$DIR/addons/rook/${ROOK_VERSION}/operator"
    local dst="$DIR/kustomize/rook/operator"

    cp -r "$src" "$dst"
    kubectl apply -k "$dst/"
    # on upgrades wait for the new version of the operator pod
    kubectl -n rook-ceph rollout status deployment/rook-ceph-operator
}

function rook_cluster_deploy() {
    local src="$DIR/addons/rook/${ROOK_VERSION}/cluster"
    local dst="$DIR/kustomize/rook/cluster"

    mkdir -p "$dst"
    cp "$src/kustomization.yaml" "$dst/"

    # resources
    cp "$src/ceph-cluster.yaml" "$dst/"
    cp "$src/ceph-block-pool.yaml" "$dst/"
    cp "$src/ceph-object-store.yaml" "$dst/"
    render_yaml_file "$src/tmpl-ceph-storage-class.yaml" > "$dst/ceph-storage-class.yaml"

    # patches
    cp "$src/patches/ceph-cluster-mons.yaml" "$dst/"
    render_yaml_file "$src/patches/tmpl-ceph-cluster-image.yaml" > "$dst/ceph-cluster-image.yaml"
    render_yaml_file "$src/patches/tmpl-ceph-block-pool-replicas.yaml" > "$dst/ceph-block-pool-replicas.yaml"
    render_yaml_file "$src/patches/tmpl-ceph-object-store.yaml" > "$dst/ceph-object-store-replicas.yaml"

    if [ "$ROOK_BLOCK_STORAGE_ENABLED" = "1" ]; then
        render_yaml_file "$src/patches/tmpl-ceph-cluster-block-storage.yaml" > "$dst/ceph-cluster-storage.yaml"
    else
        render_yaml_file "$src/patches/tmpl-ceph-cluster-storage.yaml" > "$dst/ceph-cluster-storage.yaml"
    fi

    kubectl apply -k "$dst/"
}

function rook_join() {
    rook_lvm2
}

function rook_already_applied() {
    rook_object_store_output
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
    spinnerPodRunning rook-ceph rook-ceph-agent
    spinnerPodRunning rook-ceph rook-discover
    printf "awaiting rook-ceph volume plugin\n"
    rook_flex_volume_plugin_ready_spinner
}

function rook_flex_volume_plugin_ready_spinner() {
    local delay=0.75
    local spinstr='|/-\'
    while [ ! -e /usr/libexec/kubernetes/kubelet-plugins/volume/exec/ceph.rook.io~rook-ceph/rook-ceph ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
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
    local sig=$(echo -en "${string}" | openssl sha1 -hmac "${OBJECT_STORE_SECRET_KEY}" -binary | base64)

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

function rook_lvm2() {
    local src="$DIR/addons/rook/$ROOK_VERSION"
    if commandExists lvm; then
        return
    fi
 
    if is_rhel_9_variant; then
        yum_ensure_host_package lvm2
    else
        install_host_archives "$src" lvm2
    fi
}

function rook_clients_secure {
    if [[ $(kubectl -n rook-ceph exec deploy/rook-ceph-operator -- ceph status | grep "mon is allowing insecure global_id reclaim") ]]; then 
      return 1
    fi
}

function rook_patch_insecure_clients {

    echo "Patching allowance of insecure rook clients"
    # Disabling rook global_id reclaim
    try_5m kubectl -n rook-ceph exec deploy/rook-ceph-operator -- ceph config set mon auth_allow_insecure_global_id_reclaim false

    # Checking to ensure ceph status  
    if ! spinner_until 120 rook_clients_secure; then
        logWarn "Mon is still allowing insecure clients"
    fi
}

# rook_ceph_version_deployed checks that there is only one ceph-version reported across the cluster
function rook_ceph_version_deployed() {
    local ceph_version="14.2.21"
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

# Occasionally the operator will update the mons but not the osds. This leaves the osds
# unable to run. Manually edit the version in deployments that have not been updated.
function rook_ceph_edit_version() {
    printf "${YELLOW}Ceph failed to gracefully upgrade to v14.2.21. Force-applying upgrade\n${NC}"

    kubectl -n rook-ceph get deploy --selector=ceph-version=14.2.0 -oyaml | \
        sed 's/kurlsh\/ceph:v14.2.0.*/kurlsh\/ceph:v14.2.21-9065b09-20210625/g' | \
        sed 's/kurlsh\/rook-ceph:v1.0.4.*/kurlsh\/rook-ceph:v1.0.4-14.2.21-9065b09-20210625/g' | \
        sed 's/14.2.0/14.2.21/g' \
        > /tmp/ceph.yaml

    kubectl apply -f /tmp/ceph.yaml
}
