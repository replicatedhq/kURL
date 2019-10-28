
function kubernetes_host() {
    kubernetes_load_ipvs_modules

    kubernetes_sysctl_config

    kubernetes_install_host_packages "$KUBERNETES_VERSION"

    kubernetes_install_kustomize

    load_images $DIR/packages/kubernetes/$KUBERNETES_VERSION/images
}

kubernetes_kustomize_ok() {
    if ! commandExists kustomize; then
        printf "kustomize command missing - will install it\n"
        return 1
    fi
}

function kubernetes_install_kustomize() {
    logStep "Install kustomize"

    if kubernetes_kustomize_ok; then
        logSuccess "Kustomize already installed"
        return
    fi

    case "$LSB_DIST" in
        ubuntu)
            install -m 0755 $DIR/packages/kubernetes/${KUBERNETES_VERSION}/ubuntu-${DIST_VERSION}/kustomize /usr/local/bin/
            ;;
        centos|rhel)
            install -m 0755 $DIR/packages/kubernetes/${KUBERNETES_VERSION}/rhel-7/kustomize /usr/local/bin/
            ;;
    esac

    logSuccess "Kustomize installed"
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
            commandExists kustomize || install -m 0755 DIR/packages/kubernetes/${k8sVersion}/ubuntu-${DIST_VERSION}/kustomize /usr/local/bin/
            ;;

        centos|rhel)
            rpm --upgrade --force --nodeps $DIR/packages/kubernetes/${k8sVersion}/rhel-7/*.rpm
            # TODO still required on 1.15+, and only CentOS/RHEL?
            service docker restart
            commandExists kustomize || install -m 0755 DIR/packages/kubernetes/${k8sVersion}/rhel-7/kustomize /usr/local/bin/
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
    kubectl get nodes --no-headers --selector="!node-role.kubernetes.io/master" 2>/dev/null
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
