export KUBECTL_PLUGINS_PATH=/usr/local/bin

function kubernetes_host() {
    kubernetes_load_ipvs_modules

    kubernetes_sysctl_config

    # For online always download the kubernetes.tar.gz bundle.
    # Regardless if host packages are already installed, we always inspect for newer versions
    # and/or re-install any missing or corrupted packages.
    if [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        kubernetes_get_host_packages_online "$KUBERNETES_VERSION"
    fi

    kubernetes_install_host_packages "$KUBERNETES_VERSION"

    load_images $DIR/packages/kubernetes/$KUBERNETES_VERSION/images

    install_plugins

    install_kustomize
}

function kubernetes_load_ipvs_modules() {
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
        centos|rhel|amzn)
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

    if [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        kubernetes_get_host_packages_online "$k8sVersion"
    fi

    case "$LSB_DIST" in
        ubuntu)
            export DEBIAN_FRONTEND=noninteractive
            dpkg --install --force-depends-version $DIR/packages/kubernetes/${k8sVersion}/ubuntu-${DIST_VERSION}/*.deb
            ;;

        centos|rhel|amzn)
            case "$LSB_DIST$DIST_VERSION" in
                rhel8.0|rhel8.1|rhel8.2|centos8.0|centos8.1|centos8.2)
                    rpm --upgrade --force --nodeps $DIR/packages/kubernetes/${k8sVersion}/rhel-8/*.rpm
                    # TODO still required on 1.15+, and only CentOS/RHEL?
                    if [ -n "$DOCKER_VERSION" ]; then
                        service docker restart
                    fi
                    ;;

                *)
                    rpm --upgrade --force --nodeps $DIR/packages/kubernetes/${k8sVersion}/rhel-7/*.rpm
                    # TODO still required on 1.15+, and only CentOS/RHEL?
                    if [ -n "$DOCKER_VERSION" ]; then
                        service docker restart
                    fi
                    ;;
            esac
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
    if ! commandExists kustomize; then
        printf "kustomize command missing - will install host components\n"
        return 1
    fi

    kubelet --version | grep -q "$k8sVersion"
}

function kubernetes_get_host_packages_online() {
    local k8sVersion="$1"

    if [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        curl -sSLO "$DIST_URL/kubernetes-${k8sVersion}.tar.gz"
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

function install_plugins() {
    pushd "$DIR/krew"
    tar xzvf outdated.tar.gz && mv outdated /usr/local/bin/kubectl-outdated
    tar xzvf preflight.tar.gz && mv preflight /usr/local/bin/kubectl-preflight
    tar xzvf support-bundle.tar.gz && mv support-bundle /usr/local/bin/kubectl-support_bundle
    popd

    # uninstall system-wide krew from old versions of kurl
    rm -rf /opt/replicated/krew
    sed -i '/^export KUBECTL_PLUGINS_PATH.*KREW_ROOT/d' /etc/profile
    sed -i '/^export KREW_ROOT.*replicated/d' /etc/profile
}

function install_kustomize() {
    if ! kubernetes_is_master; then
        return 0
    elif [ ! -d "$DIR/packages/kubernetes/${k8sVersion}/assets" ]; then
        echo "Kustomize package is missing in your distribution. Skipping."
        return 0
    fi

    kustomize_dir=/usr/local/bin

    pushd "$DIR/packages/kubernetes/${k8sVersion}/assets"
    for file in $(ls kustomize-*);do
        if [ "${file: -6}" == "tar.gz" ];then
            tar xf ${file}
            chmod a+x kustomize
            mv kustomize /usr/local/bin/${file%%.tar*}
        else
            # Earlier versions of kustomize weren't archived/compressed
            chmod a+x ${file}
            cp ${file} ${kustomize_dir}
        fi
    done
    popd

    if ls ${kustomize_dir}/kustomize-* 1>/dev/null 2>&1;then 
        latest_binary=$(basename $(ls ${kustomize_dir}/kustomize-* | sort -V | tail -n 1))
        
        # Link to the latest version
        ln -s -f ${kustomize_dir}/${latest_binary} ${kustomize_dir}/kustomize
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
        size="22"
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
    local nodeName="$1"
    # docker.io/envoyproxy/envoy-alpine:v1.10.0 -> envoyproxy/envoy-alpine:v1.10.0
    local image=$(echo $2 | sed 's/^docker.io\///')

    while read -r nodeImage; do
        if [ "$nodeImage" = "$image" ]; then
            return 0
        fi
    done < <(kubernetes_node_images "$nodeName")

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
    kubeadm config view 2>/dev/null | grep 'controlPlaneEndpoint:' | sed 's/controlPlaneEndpoint: \|"//g'
}
