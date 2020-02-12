export KREW_ROOT=/opt/replicated/krew
export KUBECTL_PLUGINS_PATH=${KREW_ROOT}/bin

function kubernetes_host() {
    kubernetes_load_ipvs_modules

    kubernetes_sysctl_config

    kubernetes_install_host_packages "$KUBERNETES_VERSION"

    load_images $DIR/packages/kubernetes/$KUBERNETES_VERSION/images

    install_krew
}

function kubernetes_load_ipvs_modules() {
    if [ "$IPVS" != "1" ]; then
        return
    fi
    if lsmod | grep -q ip_vs ; then
        return
    fi

    if [ "$KERNEL_MAJOR" -lt "4" ] || ([ "$KERNEL_MAJOR" -eq "4" ] && [ "$KERNEL_MINOR" -lt "19" ]); then
        modprobe nf_conntrack_ipv4
    else
        modprobe nf_conntrack
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
        centos|rhel)
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

    logStep "Install kubelet, kubeadm, kubectl and cni host packages"

    if kubernetes_host_commands_ok "$k8sVersion"; then
        logSuccess "Kubernetes host packages already installed"
        return
    fi

    if [ "$AIRGAP" != "1" ] && [ -n "$KURL_URL" ]; then
        kubernetes_get_host_packages_online "$k8sVersion"
    fi

    case "$LSB_DIST" in
        ubuntu)
            export DEBIAN_FRONTEND=noninteractive
            dpkg --install --force-depends-version $DIR/packages/kubernetes/${k8sVersion}/ubuntu-${DIST_VERSION}/*.deb
            ;;

        centos|rhel)
            rpm --upgrade --force --nodeps $DIR/packages/kubernetes/${k8sVersion}/rhel-7/*.rpm
            # TODO still required on 1.15+, and only CentOS/RHEL?
            service docker restart
            ;;
    esac

    if [ "$CLUSTER_DNS" != "$DEFAULT_CLUSTER_DNS" ]; then
        sed -i "s/$DEFAULT_CLUSTER_DNS/$CLUSTER_DNS/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    fi

    systemctl enable kubelet && systemctl start kubelet

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

    kubelet --version | grep -q "$k8sVersion"
}

function kubernetes_get_host_packages_online() {
    local k8sVersion="$1"

    if [ "$AIRGAP" != "1" ] && [ -n "$KURL_URL" ]; then
        curl -sSLO "$KURL_URL/dist/kubernetes-${k8sVersion}.tar.gz"
        tar xf kubernetes-${k8sVersion}.tar.gz
        rm kubernetes-${k8sVersion}.tar.gz
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
    curl --noproxy "*" --fail --silent --insecure "https://$(kubernetes_api_address)/healthz"
}

function spinner_kubernetes_api_healthy() {
    if ! spinner_until 120 kubernetes_api_is_healthy; then
        bail "Kubernetes API failed to report healthy"
    fi
}

function kubernetes_drain() {
    kubectl drain "$1" \
        --delete-local-data \
        --ignore-daemonsets \
        --force \
        --grace-period=30 \
        --timeout=300s \
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
    if try_1m kubectl get nodes --no-headers | awk '{ print $1 }' | grep -q "NotReady"; then
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

function install_krew() {
    if ! kubernetes_is_master; then
        return 0
    fi

    mkdir -p $KREW_ROOT

    pushd "$DIR/krew"
    tar xzf krew.tar.gz
    ./krew-linux_amd64 install --manifest=krew.yaml --archive=krew.tar.gz > /dev/null 2>&1
    tar xf index.tar -C $KREW_ROOT
    ./krew-linux_amd64 install --manifest=outdated.yaml --archive=outdated.tar.gz > /dev/null 2>&1
    ./krew-linux_amd64 install --manifest=preflight.yaml --archive=preflight.tar.gz > /dev/null 2>&1
    ./krew-linux_amd64 install --manifest=support-bundle.yaml --archive=support-bundle.tar.gz > /dev/null 2>&1
    popd

    # Fixes permission issues with 'kubectl krew'
    chmod -R 0777 /opt/replicated/krew/store
    chmod -R a+rw /opt/replicated/krew
    chmod -R a+rw /tmp/krew-downloads

    if ! grep -q KREW_ROOT /etc/profile; then
        echo "export KREW_ROOT=$KREW_ROOT" >> /etc/profile
    fi
    if ! grep -q KUBECTL_PLUGINS_PATH /etc/profile; then
        echo 'export KUBECTL_PLUGINS_PATH=$KREW_ROOT/bin' >> /etc/profile
        echo 'export PATH=$KUBECTL_PLUGINS_PATH:$PATH' >> /etc/profile
    fi
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
        fi

        if docker run --rm --net=host replicated/kurl-util:v2020.02.11-0 subnet --subnet-alloc-range "$POD_CIDR" --cidr-range "$podCidrSize" 1>/dev/null; then
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
        IP_ALLOC_RANGE="$EXISTING_POD_CIDR"
        return 0
    fi
    local size="$POD_CIDR_RANGE"
    if [ -z "$size" ]; then
        size="22"
    fi
    # find a network for the Pods, preferring start at 10.32.0.0 
    if podnet=$(docker run --rm --net=host replicated/kurl-util:v2020.02.11-0 subnet --subnet-alloc-range "10.32.0.0/16" --cidr-range "$size"); then
        echo "Found pod network: $podnet"
        POD_CIDR="$podnet"
        IP_ALLOC_RANGE="$podnet"
        return 0
    fi

    if podnet=$(docker run --rm --net=host replicated/kurl-util:v2020.02.11-0 subnet --subnet-alloc-range "10.0.0.0/8" --cidr-range "$size"); then
        echo "Found pod network: $podnet"
        POD_CIDR="$podnet"
        IP_ALLOC_RANGE="$podnet"
        return 0
    fi

    bail "Failed to find available subnet for pod network. Use the pod-cidr flag to set a pod network"
}

# This must run after discover_pod_subnet since it excludes the pod cidr
function discover_service_subnet() {
    EXISTING_SERVICE_CIDR=$(kubeadm config view 2>/dev/null | grep serviceSubnet | awk '{ print $2 }')

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
        fi

        if docker run --rm --net=host replicated/kurl-util:v2020.02.11-0 subnet --subnet-alloc-range "$SERVICE_CIDR" --cidr-range "$serviceCidrSize" --exclude-subnet "$POD_CIDR" 1>/dev/null; then
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
    if servicenet=$(docker run --rm --net=host replicated/kurl-util:v2020.02.11-0 subnet --subnet-alloc-range "10.96.0.0/16" --cidr-range "$size" --exclude-subnet "$POD_CIDR"); then
        echo "Found service network: $servicenet"
        SERVICE_CIDR="$servicenet"
        return 0
    fi

    if servicenet=$(docker run --rm --net=host replicated/kurl-util:v2020.02.11-0 subnet --subnet-alloc-range "10.0.0.0/8" --cidr-range "$size" --exclude-subnet "$POD_CIDR"); then
        echo "Found service network: $servicenet"
        SERVICE_CIDR="$servicenet"
        return 0
    fi

    bail "Failed to find available subnet for service network. Use the service-cidr flag to set a service network"
}
