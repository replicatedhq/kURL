
function kubernetes_host() {
    if [ "$SKIP_KUBERNETES_HOST" = "1" ]; then
        return 0
    fi

    kubernetes_load_ipvs_modules

    kubernetes_sysctl_config

    kubernetes_install_host_packages "$KUBERNETES_VERSION"

    # For online always download the kubernetes.tar.gz bundle.
    # Regardless if host packages are already installed, we always inspect for newer versions
    # and/or re-install any missing or corrupted packages.
    if [ "$KUBERNETES_DID_GET_HOST_PACKAGES_ONLINE" != "1" ] && [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        kubernetes_get_host_packages_online "$KUBERNETES_VERSION"
        kubernetes_get_conformance_packages_online "$KUBERNETES_VERSION"
    fi

    load_images "$DIR/packages/kubernetes/$KUBERNETES_VERSION/images"
    if [ -d "$DIR/packages/kubernetes-conformance/$KUBERNETES_VERSION/images" ]; then
        load_images "$DIR/packages/kubernetes-conformance/$KUBERNETES_VERSION/images"
    fi

    install_plugins

    install_kustomize
}

function kubernetes_load_ipvs_modules() {
    if lsmod | grep -q ip_vs ; then
        return
    fi

    if [ "$KERNEL_MAJOR" -gt "4" ] || ([ "$KERNEL_MAJOR" -eq "4" ] && [ "$KERNEL_MINOR" -ge "19" ]) || ([ "$LSB_DIST" = "rhel" ] && [ "$DIST_VERSION" = "8.3" ]) || ([ "$LSB_DIST" = "centos" ] && [ "$DIST_VERSION" = "8.3" ]) || ([ "$LSB_DIST" = "ol" ] && [ "$DIST_VERSION" = "8.3" ]); then
        modprobe nf_conntrack
    else
        modprobe nf_conntrack_ipv4
    fi

    modprobe ip_vs
    modprobe ip_vs_rr
    modprobe ip_vs_wrr
    modprobe ip_vs_sh

    echo 'nf_conntrack_ipv4' > /etc/modules-load.d/replicated-ipvs.conf
    echo 'ip_vs' >> /etc/modules-load.d/replicated-ipvs.conf
    echo 'ip_vs_rr' >> /etc/modules-load.d/replicated-ipvs.conf
    echo 'ip_vs_wrr' >> /etc/modules-load.d/replicated-ipvs.conf
    echo 'ip_vs_sh' >> /etc/modules-load.d/replicated-ipvs.conf
}

function kubernetes_sysctl_config() {
    case "$LSB_DIST" in
        # TODO I've only seen these disabled on centos/rhel but should be safe for ubuntu
        centos|rhel|amzn|ol)
            echo "net.bridge.bridge-nf-call-ip6tables = 1" > /etc/sysctl.d/k8s.conf
            echo "net.bridge.bridge-nf-call-iptables = 1" >> /etc/sysctl.d/k8s.conf
            echo "net.ipv4.conf.all.forwarding = 1" >> /etc/sysctl.d/k8s.conf

            sysctl --system
        ;;
    esac
}

# k8sVersion is an argument because this may be used to install step versions of K8s during an upgrade
# to the target version
function kubernetes_install_host_packages() {
    k8sVersion=$1

    logStep "Install kubelet, kubectl and cni host packages"

    if kubernetes_host_commands_ok "$k8sVersion"; then
        logSuccess "Kubernetes host packages already installed"
        return
    fi

    if [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        kubernetes_get_host_packages_online "$k8sVersion"
        kubernetes_get_conformance_packages_online "$k8sVersion"
    fi

    cat > "$DIR/tmp-kubeadm.conf" <<EOF
# Note: This dropin only works with kubeadm and kubelet v1.11+
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
# This is a file that "kubeadm init" and "kubeadm join" generates at runtime, populating the KUBELET_KUBEADM_ARGS variable dynamically
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
# This is a file that the user can use for overrides of the kubelet args as a last resort. Preferably, the user should use
# the .NodeRegistration.KubeletExtraArgs object in the configuration files instead. KUBELET_EXTRA_ARGS should be sourced from this file.
EnvironmentFile=-/etc/__ENV_LOCATION__/kubelet
ExecStart=
ExecStart=/usr/bin/kubelet \$KUBELET_KUBECONFIG_ARGS \$KUBELET_CONFIG_ARGS \$KUBELET_KUBEADM_ARGS \$KUBELET_EXTRA_ARGS
EOF

    case "$LSB_DIST" in
        ubuntu)
            sed "s:__ENV_LOCATION__:default:g" -i "$DIR/tmp-kubeadm.conf"
            export DEBIAN_FRONTEND=noninteractive
            dpkg --install --force-depends-version $DIR/packages/kubernetes/${k8sVersion}/ubuntu-${DIST_VERSION}/*.deb
            ;;

        centos|rhel|amzn|ol)
            case "$LSB_DIST$DIST_VERSION_MAJOR" in
                rhel8|centos8)
                    sed "s:__ENV_LOCATION__:sysconfig:g" -i "$DIR/tmp-kubeadm.conf"
                    rpm --upgrade --force --nodeps $DIR/packages/kubernetes/${k8sVersion}/rhel-8/*.rpm
                    ;;

                *)
                    sed "s:__ENV_LOCATION__:sysconfig:g" -i "$DIR/tmp-kubeadm.conf"
                    rpm --upgrade --force --nodeps $DIR/packages/kubernetes/${k8sVersion}/rhel-7/*.rpm
                    ;;
            esac
        ;;

        *)
            bail "Kubernetes host package install is not supported on ${LSB_DIST} ${DIST_MAJOR}"
        ;;
    esac

    # Update crictl: https://listman.redhat.com/archives/rhsa-announce/2019-October/msg00038.html 
    tar -C /usr/bin -xzf "$DIR/packages/kubernetes/${k8sVersion}/assets/crictl-linux-amd64.tar.gz"
    chmod a+rx /usr/bin/crictl

    # Install Kubeadm from binary (see kubernetes.io)
    cp -f "$DIR/packages/kubernetes/${k8sVersion}/assets/kubeadm" /usr/bin/
    chmod a+rx /usr/bin/kubeadm

    mkdir -p /etc/systemd/system/kubelet.service.d
    cp -f "$DIR/tmp-kubeadm.conf" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    chmod 640 /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

    if [ "$CLUSTER_DNS" != "$DEFAULT_CLUSTER_DNS" ]; then
        sed -i "s/$DEFAULT_CLUSTER_DNS/$CLUSTER_DNS/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    fi

    echo "Restarting Kubelet"
    systemctl daemon-reload
    systemctl enable kubelet && systemctl restart kubelet

    logSuccess "Kubernetes host packages installed"
}

kubernetes_host_commands_ok() {
    local k8sVersion=$1

    if ! commandExists kubelet; then
        printf "kubelet command missing - will install host components\n"
        return 1
    fi
    if ! commandExists kubeadm; then
        printf "kubeadm command missing - will install host components\n"
        return 1
    fi
    if ! commandExists kubectl; then
        printf "kubectl command missing - will install host components\n"
        return 1
    fi
    if ! ( PATH=$PATH:/usr/local/bin; commandExists kustomize ); then
        printf "kustomize command missing - will install host components\n"
        return 1
    fi
    if ! commandExists crictl; then
        printf "crictl command missing - will install host components\n"
        return 1
    fi
    local currentCrictlVersion=$(crictl --version | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+')
    semverCompare "$currentCrictlVersion" "$CRICTL_VERSION"
    if [ "$SEMVER_COMPARE_RESULT" = "-1" ]; then
        printf "crictl command upgrade available - will install host components\n"
        return 1
    fi

    kubelet --version | grep -q "$k8sVersion"
}

KUBERNETES_DID_GET_HOST_PACKAGES_ONLINE=
function kubernetes_get_host_packages_online() {
    local k8sVersion="$1"

    if [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        rm -rf "$DIR/packages/kubernetes/${k8sVersion}" # Cleanup broken/incompatible packages from failed runs

        local package="kubernetes-${k8sVersion}.tar.gz"
        package_download "${package}"
        tar xf "$(package_filepath "${package}")"
        # rm "${package}"

        KUBERNETES_DID_GET_HOST_PACKAGES_ONLINE=1
    fi
}

function kubernetes_get_conformance_packages_online() {
    local k8sVersion="$1"

    if [ -z "$SONOBUOY_VERSION" ]; then
        return
    fi

    # we only build conformance packages for 1.17.0+
    # this variable is not yet set for rke2 or k3s installs
    if [ -n "$KUBERNETES_TARGET_VERSION_MINOR" ] && [ "$KUBERNETES_TARGET_VERSION_MINOR" -lt "17" ]; then
        return
    fi

    if [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        rm -rf "$DIR/packages/kubernetes-conformance/${k8sVersion}" # Cleanup broken/incompatible packages from failed runs

        local package="kubernetes-conformance-${k8sVersion}.tar.gz"
        package_download "${package}"
        tar xf "$(package_filepath "${package}")"
        # rm "${package}"
    fi
}

function kubernetes_masters() {
    kubectl get nodes --no-headers --selector="node-role.kubernetes.io/master"
}

function kubernetes_remote_masters() {
    kubectl get nodes --no-headers --selector="node-role.kubernetes.io/master,kubernetes.io/hostname!=$(hostname)" 2>/dev/null
}

function kubernetes_workers() {
    kubectl get node --no-headers --selector='!node-role.kubernetes.io/master' 2>/dev/null
}

# exit 0 if there are any remote workers or masters
function kubernetes_has_remotes() {
    if ! kubernetes_api_is_healthy; then
        # assume this is a new install
        return 1
    fi

    local count=$(kubectl get nodes --no-headers --selector="kubernetes.io/hostname!=$(hostname)" 2>/dev/null | wc -l)
    if [ "$count" -gt "0" ]; then
        return 0
    fi

    return 1
}

function kubernetes_api_address() {
    if [ -n "$LOAD_BALANCER_ADDRESS" ]; then
        echo "${LOAD_BALANCER_ADDRESS}:${LOAD_BALANCER_PORT}"
        return
    fi
    echo "${PRIVATE_ADDRESS}:6443"
}

function kubernetes_api_is_healthy() {
    ${K8S_DISTRO}_api_is_healthy
}

function containerd_is_healthy() {
    ctr -a "$(${K8S_DISTRO}_get_containerd_sock)" images list &> /dev/null
}

function spinner_kubernetes_api_healthy() {
    if ! spinner_until 120 kubernetes_api_is_healthy; then
        bail "Kubernetes API failed to report healthy"
    fi
}

function spinner_containerd_is_healthy() {
    if ! spinner_until 120 containerd_is_healthy; then
        bail "Containerd failed to restart"
    fi
}

# With AWS NLB kubectl commands may fail to connect to the Kubernetes API immediately after a single
# successful health check
function spinner_kubernetes_api_stable() {
    for i in {1..10}; do
        sleep 1
        spinner_kubernetes_api_healthy
    done
}

function kubernetes_drain() {
    kubectl drain "$1" \
        --delete-local-data \
        --ignore-daemonsets \
        --force \
        --grace-period=30 \
        --timeout=120s \
        --pod-selector 'app notin (rook-ceph-mon,rook-ceph-osd,rook-ceph-osd-prepare,rook-ceph-operator,rook-ceph-agent),k8s-app!=kube-dns' || true
}

function kubernetes_node_has_version() {
    local name="$1"
    local version="$2"

    local actual_version="$(try_1m kubernetes_node_kubelet_version $name)"

    [ "$actual_version" = "v${version}" ]
}

function kubernetes_node_kubelet_version() {
    local name="$1"

    kubectl get node "$name" -o=jsonpath='{@.status.nodeInfo.kubeletVersion}'
}

function kubernetes_any_remote_master_unupgraded() {
    while read -r master; do
        local name=$(echo $master | awk '{ print $1 }')
        if ! kubernetes_node_has_version "$name" "$KUBERNETES_VERSION"; then
            return 0
        fi
    done < <(kubernetes_remote_masters)
    return 1
}

function kubernetes_any_worker_unupgraded() {
    while read -r worker; do
        local name=$(echo $worker | awk '{ print $1 }')
        if ! kubernetes_node_has_version "$name" "$KUBERNETES_VERSION"; then
            return 0
        fi
    done < <(kubernetes_workers)
    return 1
}

function kubelet_version() {
    kubelet --version | cut -d ' ' -f 2 | sed 's/v//'
}

function kubernetes_nodes_ready() {
    if try_1m kubectl get nodes --no-headers | awk '{ print $2 }' | grep -q "NotReady"; then
        return 1
    fi
    return 0
}

function kubernetes_scale_down() {
    local ns="$1"
    local kind="$2"
    local name="$3"

    if ! kubernetes_resource_exists "$ns" "$kind" "$name"; then
        return 0
    fi

    kubectl -n "$ns" scale "$kind" "$name" --replicas=0
}

function kubernetes_secret_value() {
    local ns="$1"
    local name="$2"
    local key="$3"

    kubectl -n "$ns" get secret "$name" -ojsonpath="{ .data.$key }" 2>/dev/null | base64 --decode
}

function kubernetes_is_master() {
    if [ "$MASTER" = "1" ]; then
        return 0
    elif [ -f /etc/kubernetes/manifests/kube-apiserver.yaml ]; then
        return 0
    else
        return 1
    fi
}

function discover_pod_subnet() {
    local excluded=""
    if ! ip route show src "$PRIVATE_ADDRESS" | awk '{ print $1 }' | grep -q '/'; then
        excluded="--exclude-subnet=${PRIVATE_ADDRESS}/16"
    fi

    if [ -n "$POD_CIDR" ]; then
        local podCidrSize=$(echo $POD_CIDR | awk -F'/' '{ print $2 }')

        # if pod-cidr flag and pod-cidr-range are both set, validate pod-cidr is as large as pod-cidr-range
        if [ -n "$POD_CIDR_RANGE" ]; then
            if [ "$podCidrSize" -gt "$POD_CIDR_RANGE" ]; then
                bail "Pod cidr must be at least /$POD_CIDR_RANGE"
            fi
        fi

        # if pod cidr flag matches existing weave pod cidr don't validate
        if [ "$POD_CIDR" = "$EXISTING_POD_CIDR" ]; then
            return 0
        elif [ -n "$EXISTING_POD_CIDR" ]; then
            bail "Pod cidr cannot be changed to $POD_CIDR because existing cidr is $EXISTING_POD_CIDR"
        fi

        if $DIR/bin/subnet --subnet-alloc-range "$POD_CIDR" --cidr-range "$podCidrSize" "$excluded" 1>/dev/null; then
            return 0
        fi

        printf "${RED}Pod cidr ${POD_CIDR} overlaps with existing route. Continue? ${NC}"
        if ! confirmY "-t 60"; then
            exit 1
        fi
        return 0
    fi
    # detected from weave device
    if [ -n "$EXISTING_POD_CIDR" ]; then
        POD_CIDR="$EXISTING_POD_CIDR"
        return 0
    fi
    local size="$POD_CIDR_RANGE"
    if [ -z "$size" ]; then
        size="20"
    fi
    # find a network for the Pods, preferring start at 10.32.0.0 
    if podnet=$($DIR/bin/subnet --subnet-alloc-range "10.32.0.0/16" --cidr-range "$size" "$excluded"); then
        echo "Found pod network: $podnet"
        POD_CIDR="$podnet"
        return 0
    fi

    if podnet=$($DIR/bin/subnet --subnet-alloc-range "10.0.0.0/8" --cidr-range "$size" "$excluded"); then
        echo "Found pod network: $podnet"
        POD_CIDR="$podnet"
        return 0
    fi

    bail "Failed to find available subnet for pod network. Use the pod-cidr flag to set a pod network"
}

# This must run after discover_pod_subnet since it excludes the pod cidr
function discover_service_subnet() {
    local excluded="--exclude-subnet=$POD_CIDR"
    if ! ip route show src "$PRIVATE_ADDRESS" | awk '{ print $1 }' | grep -q '/'; then
        excluded="$excluded,${PRIVATE_ADDRESS}/16"
    fi

    EXISTING_SERVICE_CIDR=$(maybe kubeadm_cluster_configuration | grep serviceSubnet | awk '{ print $2 }')

    if [ -n "$SERVICE_CIDR" ]; then
        local serviceCidrSize=$(echo $SERVICE_CIDR | awk -F'/' '{ print $2 }')

        # if service-cidr flag and service-cidr-range are both set, validate service-cidr is as large as service-cidr-range
        if [ -n "$SERVICE_CIDR_RANGE" ]; then
            if [ "$serviceCidrSize" -gt "$SERVICE_CIDR_RANGE" ]; then
                bail "Service cidr must be at least /$SERVICE_CIDR_RANGE"
            fi
        fi

        # if service-cidr flag matches existing service cidr don't validate
        if [ "$SERVICE_CIDR" = "$EXISTING_SERVICE_CIDR" ]; then
            return 0
        elif [ -n "$EXISTING_SERVICE_CIDR" ]; then
            bail "Service cidr cannot be changed to $SERVICE_CIDR because existing cidr is $EXISTING_SERVICE_CIDR"
        fi

        if $DIR/bin/subnet --subnet-alloc-range "$SERVICE_CIDR" --cidr-range "$serviceCidrSize" "$excluded" 1>/dev/null; then
            return 0
        fi

        printf "${RED}Service cidr ${SERVICE_CIDR} overlaps with existing route. Continue? ${NC}"
        if ! confirmY "-t 60"; then
            exit 1
        fi
        return 0
    fi

    if [ -n "$EXISTING_SERVICE_CIDR" ]; then
        echo "Using existing service cidr ${EXISTING_SERVICE_CIDR}"
        SERVICE_CIDR="$EXISTING_SERVICE_CIDR"
        return 0
    fi

    local size="$SERVICE_CIDR_RANGE"
    if [ -z "$size" ]; then
        size="22"
    fi

    # find a network for the services, preferring start at 10.96.0.0 
    if servicenet=$($DIR/bin/subnet --subnet-alloc-range "10.96.0.0/16" --cidr-range "$size" "$excluded"); then
        echo "Found service network: $servicenet"
        SERVICE_CIDR="$servicenet"
        return 0
    fi

    if servicenet=$($DIR/bin/subnet --subnet-alloc-range "10.0.0.0/8" --cidr-range "$size" "$excluded"); then
        echo "Found service network: $servicenet"
        SERVICE_CIDR="$servicenet"
        return 0
    fi

    bail "Failed to find available subnet for service network. Use the service-cidr flag to set a service network"
}

function kubernetes_node_images() {
    local nodeName="$1"

    kubectl get node "$nodeName" -ojsonpath="{range .status.images[*]}{ range .names[*] }{ @ }{'\n'}{ end }{ end }"
}

function list_all_required_images() {
    find packages/kubernetes/$KUBERNETES_VERSION -type f -name Manifest 2>/dev/null | xargs cat | grep -E '^image' | grep -v no_remote_load | awk '{ print $3 }'

    if [ -n "$STEP_VERSION" ]; then
        find packages/kubernetes/$STEP_VERSION -type f -name Manifest 2>/dev/null | xargs cat | grep -E '^image' | grep -v no_remote_load | awk '{ print $3 }'
    fi

    if [ -n "$DOCKER_VERSION" ]; then
        find packages/docker/$DOCKER_VERSION -type f -name Manifest 2>/dev/null | xargs cat | grep -E '^image' | grep -v no_remote_load | awk '{ print $3 }'
    fi

    if [ -n "$WEAVE_VERSION" ]; then
        find addons/weave/$WEAVE_VERSION -type f -name Manifest 2>/dev/null | xargs cat | grep -E '^image' | grep -v no_remote_load | awk '{ print $3 }'
    fi

    if [ -n "$ROOK_VERSION" ]; then
        find addons/rook/$ROOK_VERSION -type f -name Manifest 2>/dev/null | xargs cat | grep -E '^image' | grep -v no_remote_load | awk '{ print $3 }'
    fi

    if [ -n "$OPENEBS_VERSION" ]; then
        find addons/openebs/$OPENEBS_VERSION -type f -name Manifest 2>/dev/null | xargs cat | grep -E '^image' | grep -v no_remote_load | awk '{ print $3 }'
    fi

    if [ -n "$LONGHORN_VERSION" ]; then
        find addons/longhorn/$LONGHORN_VERSION -type f -name Manifest 2>/dev/null | xargs cat | grep -E '^image' | grep -v no_remote_load | awk '{ print $3 }'
    fi

    if [ -n "$MINIO_VERSION" ]; then
        find addons/minio/$MINIO_VERSION -type f -name Manifest 2>/dev/null | xargs cat | grep -E '^image' | grep -v no_remote_load | awk '{ print $3 }'
    fi

    if [ -n "$CONTOUR_VERSION" ]; then
        find addons/contour/$CONTOUR_VERSION -type f -name Manifest 2>/dev/null | xargs cat | grep -E '^image' | grep -v no_remote_load | awk '{ print $3 }'
    fi

    if [ -n "$REGISTRY_VERSION" ]; then
        find addons/registry/$REGISTRY_VERSION -type f -name Manifest 2>/dev/null | xargs cat | grep -E '^image' | grep -v no_remote_load | awk '{ print $3 }'
    fi

    if [ -n "$PROMETHEUS_VERSION" ]; then
        find addons/prometheus/$PROMETHEUS_VERSION -type f -name Manifest 2>/dev/null | xargs cat | grep -E '^image' | grep -v no_remote_load | awk '{ print $3 }'
    fi

    if [ -n "$KOTSADM_VERSION" ]; then
        find addons/kotsadm/$KOTSADM_VERSION -type f -name Manifest 2>/dev/null | xargs cat | grep -E '^image' | grep -v no_remote_load | awk '{ print $3 }'
    fi

    if [ -n "$FLUENTD_VERSION" ]; then
        find addons/fluentd/$FLUENTD_VERSION -type f -name Manifest 2>/dev/null | xargs cat | grep -E '^image' | grep -v no_remote_load | awk '{ print $3 }'
    fi

    if [ -n "$VELERO_VERSION" ]; then
        find addons/velero/$VELERO_VERSION -type f -name Manifest 2>/dev/null | xargs cat | grep -E '^image' | grep -v no_remote_load | awk '{ print $3 }'
    fi

    if [ -n "$EKCO_VERSION" ]; then
        find addons/ekco/$EKCO_VERSION -type f -name Manifest 2>/dev/null | xargs cat | grep -E '^image' | grep -v no_remote_load | awk '{ print $3 }'
    fi

    if [ -n "$CERT_MANAGER_VERSION" ]; then
        find addons/cert-manager/$CERT_MANAGER_VERSION -type f -name Manifest 2>/dev/null | xargs cat | grep -E '^image' | grep -v no_remote_load | awk '{ print $3 }'
    fi

    if [ -n "$METRICS_SERVER_VERSION" ]; then
        find addons/metrics-server/$METRICS_SERVER_VERSION -type f -name Manifest 2>/dev/null | xargs cat | grep -E '^image' | grep -v no_remote_load | awk '{ print $3 }'
    fi

    if [ -n "$SONOBUOY_VERSION" ]; then
        find addons/sonobuoy/$SONOBUOY_VERSION -type f -name Manifest 2>/dev/null | xargs cat | grep -E '^image' | grep -v no_remote_load | awk '{ print $3 }'
    fi
}

function kubernetes_node_has_all_images() {
    local nodeName="$1"

    while read -r image; do
        if ! kubernetes_node_has_image "$nodeName" "$image"; then
            printf "\n${YELLOW}Node $nodeName missing image $image${NC}\n"
            return 1
        fi
    done < <(list_all_required_images)
}

function kubernetes_node_has_image() {
    local node_name="$1"
    local image="$2"

    while read -r node_image; do
        if [ "$(canonical_image_name "$node_image")" = "$(canonical_image_name "$image")" ]; then
            return 0
        fi
    done < <(kubernetes_node_images "$node_name")

    return 1
}

KUBERNETES_REMOTE_PRIMARIES=()
KUBERNETES_REMOTE_PRIMARY_VERSIONS=()
function kubernetes_get_remote_primaries() {
    while read -r primary; do
        local name=$(echo $primary | awk '{ print $1 }')
        local version="$(try_1m kubernetes_node_kubelet_version $name)"

        KUBERNETES_REMOTE_PRIMARIES+=( $name )
        KUBERNETES_REMOTE_PRIMARY_VERSIONS+=( $version )
    done < <(kubernetes_remote_masters)
}

KUBERNETES_SECONDARIES=()
KUBERNETES_SECONDARY_VERSIONS=()
function kubernetes_get_secondaries() {
    while read -r secondary; do
        local name=$(echo $secondary | awk '{ print $1 }')
        local version="$(try_1m kubernetes_node_kubelet_version $name)"

        KUBERNETES_SECONDARIES+=( $name )
        KUBERNETES_SECONDARY_VERSIONS+=( $version )
    done < <(kubernetes_workers)
}

function kubernetes_load_balancer_address() {
    maybe kubeadm_cluster_configuration | grep 'controlPlaneEndpoint:' | sed 's/controlPlaneEndpoint: \|"//g'
}

function kubernetes_pod_started() {
    local name=$1
    local namespace=$2

    local phase=$(kubectl -n $namespace get pod $name -ojsonpath='{ .status.phase }')
    case "$phase" in
        Running|Failed|Succeeded)
            return 0
            ;;
    esac

    return 1
}

function kubernetes_pod_completed() {
    local name=$1
    local namespace=$2

    local phase=$(kubectl -n $namespace get pod $name -ojsonpath='{ .status.phase }')
    case "$phase" in
        Failed|Succeeded)
            return 0
            ;;
    esac

    return 1
}

function kubernetes_pod_succeeded() {
    local name="$1"
    local namespace="$2"

    local phase=$(kubectl -n $namespace get pod $name -ojsonpath='{ .status.phase }')
    [ "$phase" = "Succeeded" ]
}

function kubernetes_is_current_cluster() {
    local api_service_address="$1"
    if cat /etc/kubernetes/kubelet.conf 2>/dev/null | grep -q "${api_service_address}"; then
        return 0
    fi
    if cat /opt/replicated/kubeadm.conf 2>/dev/null | grep -q "${api_service_address}"; then
        return 0
    fi
    return 1
}

function kubernetes_is_join_node() {
    if cat /opt/replicated/kubeadm.conf 2>/dev/null | grep -q 'kind: JoinConfiguration'; then
        return 0
    fi
    return 1
}

function kubernetes_is_installed() {
    if kubectl cluster-info >/dev/null 2>&1 ; then
        return 0
    fi
    if ps aux | grep '[k]ubelet' ; then
        return 0
    fi
    if commandExists kubelet ; then
        return 0
    fi
    return 1
}

function kubeadm_cluster_configuration() {
    kubectl get cm -o yaml -n kube-system kubeadm-config -ojsonpath='{ .data.ClusterConfiguration }'
}

function kubeadm_cluster_status() {
    kubectl get cm -o yaml -n kube-system kubeadm-config -ojsonpath='{ .data.ClusterStatus }'
}

function check_network() {
	logStep "Checking cluster networking"

    if ! kubernetes_any_node_ready; then
        echo "Waiting for node to report Ready"
        spinner_until 300 kubernetes_any_node_ready
    fi

    kubectl delete pods kurlnet-client kurlnet-server --force --grace-period=0 &>/dev/null || true

	cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: kurlnet
spec:
  selector:
    app: kurlnet
    component: server
  ports:
  - protocol: TCP
    port: 8080
    targetPort: 8080
---
apiVersion: v1
kind: Pod
metadata:
 name: kurlnet-server
 labels:
   app: kurlnet
   component: server
spec:
  restartPolicy: OnFailure
  containers:
  - name: pod
    image: $KURL_UTIL_IMAGE
    command: [/usr/local/bin/network, --server]
---
apiVersion: v1
kind: Pod
metadata:
 name: kurlnet-client
 labels:
   app: kurlnet
   component: client
spec:
  restartPolicy: OnFailure
  containers:
  - name: pod
    image: $KURL_UTIL_IMAGE
    command: [/usr/local/bin/network, --client, --address, http://kurlnet.default.svc.cluster.local:8080]
EOF

    echo "Waiting for kurlnet-client pod to start"
    spinner_until 120 kubernetes_pod_started kurlnet-client default

    # Wait up to 1 minute for the network check to succeed. If it's still failing print the client
    # logs to help with troubleshooting. Then show the spinner indefinitely so that the script will
    # proceed as soon as the problem is fixed.
    if spinner_until 60 kubernetes_pod_completed kurlnet-client default; then
        if kubernetes_pod_succeeded kurlnet-client default; then
            kubectl delete pods kurlnet-client kurlnet-server --force --grace-period=0
            kubectl delete service kurlnet
            return 0
        fi
        bail "kurlnet-client pod failed to validate cluster networking"
    fi

    printf "${YELLOW}There appears to be a problem with cluster networking${NC}\n"
    kubectl logs kurlnet-client

    if spinner_until -1 kubernetes_pod_completed kurlnet-client default; then
        if kubernetes_pod_succeeded kurlnet-client default; then
            kubectl delete pods kurlnet-client kurlnet-server --force --grace-period=0
            kubectl delete service kurlnet
            return 0
        fi
        bail "kurlnet-client pod failed to validate cluster networking"
    fi
}

function kubernetes_default_service_account_exists() {
    kubectl -n default get serviceaccount default &>/dev/null
}

function kubernetes_service_exists() {
    kubectl -n default get service kubernetes &>/dev/null
}

function kubernetes_any_node_ready() {
    if kubectl get nodes --no-headers 2>/dev/null | awk '{ print $2 }' | grep -v 'NotReady' | grep -q 'Ready' ; then
        return 0
    fi
    return 1
}
