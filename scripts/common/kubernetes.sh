#!/bin/bash

function kubernetes_pre_init() {
    if is_rhel_9_variant ; then
        # git is packaged in the bundle and installed in other oses by
        # kubernetes_install_host_packages
        yum_ensure_host_package git
    fi
}

function kubernetes_host() {
    kubernetes_load_modules
    kubernetes_load_ipv4_modules
    kubernetes_load_ipv6_modules
    kubernetes_load_ipvs_modules

    if [ "$SKIP_KUBERNETES_HOST" = "1" ]; then
        return 0
    fi

    kubernetes_install_host_packages "$KUBERNETES_VERSION"

    kubernetes_load_images "$KUBERNETES_VERSION"

    install_plugins

    install_kustomize
}

function kubernetes_load_images() {
    local version="$1"

    local varname="KUBERNETES_IMAGES_LOADED_${version//./_}"
    if [ "${!varname:-}" = "1" ]; then
        # images already loaded for this version
        return 0
    fi

    load_images "$DIR/packages/kubernetes/$version/images"
    if [ -n "$SONOBUOY_VERSION" ] && [ -d "$DIR/packages/kubernetes-conformance/$version/images" ]; then
        load_images "$DIR/packages/kubernetes-conformance/$version/images"
    fi

    declare -g "$varname"=1
}

function kubernetes_get_packages() {
    if [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        kubernetes_get_host_packages_online "$KUBERNETES_VERSION"
        kubernetes_get_conformance_packages_online "$KUBERNETES_VERSION"
    fi
}

# kubernetes_maybe_get_packages_airgap downloads kubernetes packages if they are not already present
function kubernetes_maybe_get_packages_airgap() {
    if [ "$AIRGAP" != "1" ]; then
        return
    fi
    if [ -d "$DIR/packages/kubernetes/$KUBERNETES_VERSION/assets" ]; then
        return
    fi
    addon_fetch_airgap "kubernetes" "$KUBERNETES_VERSION"
}

function kubernetes_load_ipvs_modules() {
    if lsmod | grep -q ip_vs ; then
        return
    fi

    local mod_nf_conntrack="nf_conntrack_ipv4"
    if [ "$KERNEL_MAJOR" -gt "4" ] || \
        { [ "$KERNEL_MAJOR" -eq "4" ] && [ "$KERNEL_MINOR" -ge "19" ]; } || \
        {
            { [ "$LSB_DIST" = "ol" ] || [ "$LSB_DIST" = "rhel" ] || [ "$LSB_DIST" = "centos" ] || [ "$LSB_DIST" = "rocky" ]; } && \
            { [ "$DIST_VERSION_MAJOR" = "8" ] || [ "$DIST_VERSION_MAJOR" = "9" ] || [ "$DIST_VERSION_MINOR"  -gt "2" ]; }; \
        }; then
        mod_nf_conntrack="nf_conntrack"
    fi

    modprobe $mod_nf_conntrack
    rm -f /etc/modules-load.d/replicated-ipvs.conf

    echo "Adding kernel modules ip_vs, ip_vs_rr, ip_vs_wrr, and ip_vs_sh"
    modprobe ip_vs
    modprobe ip_vs_rr
    modprobe ip_vs_wrr
    modprobe ip_vs_sh

    echo $mod_nf_conntrack > /etc/modules-load.d/99-replicated-ipvs.conf
    # shellcheck disable=SC2129
    echo "ip_vs" >> /etc/modules-load.d/99-replicated-ipvs.conf
    echo "ip_vs_rr" >> /etc/modules-load.d/99-replicated-ipvs.conf
    echo "ip_vs_wrr" >> /etc/modules-load.d/99-replicated-ipvs.conf
    echo "ip_vs_sh" >> /etc/modules-load.d/99-replicated-ipvs.conf
}

function kubernetes_load_modules() {
    if ! lsmod | grep -Fq br_netfilter ; then
        echo "Adding kernel module br_netfilter"
        modprobe br_netfilter
    fi
    echo "br_netfilter" > /etc/modules-load.d/99-replicated.conf
}

function kubernetes_load_ipv4_modules() {
    if [ "$IPV6_ONLY" = "1" ]; then
        return 0
    fi

    if ! lsmod | grep -q ^ip_tables ; then
        echo "Adding kernel module ip_tables"
        modprobe ip_tables
    fi
    echo "ip_tables" > /etc/modules-load.d/99-replicated-ipv4.conf

    echo "net.bridge.bridge-nf-call-iptables = 1" > /etc/sysctl.d/99-replicated-ipv4.conf
    echo "net.ipv4.conf.all.forwarding = 1" >> /etc/sysctl.d/99-replicated-ipv4.conf

    sysctl --system

    if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "0" ]; then
        bail "Failed to enable IP forwarding."
    fi
}

function kubernetes_load_ipv6_modules() {
    if [ "$IPV6_ONLY" != "1" ]; then
        return 0
    fi

    if ! lsmod | grep -q ^ip6_tables ; then
        echo "Adding kernel module ip6_tables"
        modprobe ip6_tables
    fi
    echo "ip6_tables" > /etc/modules-load.d/99-replicated-ipv6.conf

    echo "net.bridge.bridge-nf-call-ip6tables = 1" > /etc/sysctl.d/99-replicated-ipv6.conf
    echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.d/99-replicated-ipv6.conf

    sysctl --system

    if [ "$(cat /proc/sys/net/ipv6/conf/all/forwarding)" = "0" ]; then
        bail "Failed to enable IPv6 forwarding."
    fi
}

# k8sVersion is an argument because this may be used to install step versions of K8s during an upgrade
# to the target version
function kubernetes_install_host_packages() {
    k8sVersion=$1

    logStep "Install kubelet, kubectl and cni host packages"

    if kubernetes_host_commands_ok "$k8sVersion"; then
        logSuccess "Kubernetes host packages already installed"

        kubernetes_cis_chmod_kubelet_service_file

        # less command is broken if libtinfo.so.5 is missing in amazon linux 2
        if [ "$LSB_DIST" == "amzn" ] && [ "$AIRGAP" != "1" ] && ! file_exists "/usr/lib64/libtinfo.so.5"; then
            if [ -d "$DIR/packages/kubernetes/${k8sVersion}/assets" ]; then
                install_host_packages "${DIR}/packages/kubernetes/${k8sVersion}" ncurses-compat-libs
            fi
        fi
        
        return
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
            ;;

        centos|rhel|ol|rocky|amzn)
            sed "s:__ENV_LOCATION__:sysconfig:g" -i "$DIR/tmp-kubeadm.conf"
            ;;

        *)
            bail "Kubernetes host package install is not supported on ${LSB_DIST} ${DIST_MAJOR}"
        ;;
    esac

    if is_rhel_9_variant ; then
        # ensure git in kubernetes_pre_init
        install_host_packages "${DIR}/packages/kubernetes/${k8sVersion}" "kubelet-${k8sVersion}" "kubectl-${k8sVersion}"
    else
        install_host_packages "${DIR}/packages/kubernetes/${k8sVersion}" "kubelet-${k8sVersion}" "kubectl-${k8sVersion}" git
    fi

    # Update crictl: https://listman.redhat.com/archives/rhsa-announce/2019-October/msg00038.html 
    tar -C /usr/bin -xzf "$DIR/packages/kubernetes/${k8sVersion}/assets/crictl-linux-amd64.tar.gz"
    chmod a+rx /usr/bin/crictl

    # Install Kubeadm from binary (see kubernetes.io)
    cp -f "$DIR/packages/kubernetes/${k8sVersion}/assets/kubeadm" /usr/bin/
    chmod a+rx /usr/bin/kubeadm

    mkdir -p /etc/systemd/system/kubelet.service.d
    cp -f "$DIR/tmp-kubeadm.conf" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    chmod 600 /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

    if [ "$CLUSTER_DNS" != "$DEFAULT_CLUSTER_DNS" ]; then
        sed -i "s/$DEFAULT_CLUSTER_DNS/$CLUSTER_DNS/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    fi

    echo "Restarting Kubelet"
    systemctl daemon-reload
    systemctl enable kubelet && systemctl restart kubelet

    logSuccess "Kubernetes host packages installed"
}

# kubernetes_cis_chmod_kubelet_service_file fixes the following CIS benchmark test:
# [FAIL] 4.1.1 Ensure that the kubelet service file permissions are set to 600 or more restrictive (Automated)
function kubernetes_cis_chmod_kubelet_service_file() {
    if [ -f /etc/systemd/system/kubelet.service.d/10-kubeadm.conf ]; then
        chmod 600 /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    fi
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

function kubernetes_get_host_packages_online() {
    local k8sVersion="$1"

    if [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        rm -rf "$DIR/packages/kubernetes/${k8sVersion}" # Cleanup broken/incompatible packages from failed runs

        local package="kubernetes-${k8sVersion}.tar.gz"
        package_download "${package}"
        tar xf "$(package_filepath "${package}")"
        # rm "${package}"
    fi
}

function kubernetes_get_conformance_packages_online() {
    local k8sVersion="$1"

    if [ -z "$SONOBUOY_VERSION" ]; then
        return
    fi

    # we only build conformance packages for 1.17.0+
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
    kubectl get nodes --no-headers --selector="$(kubernetes_get_control_plane_label)"
}

function kubernetes_remote_nodes() {
    kubectl get nodes --ignore-not-found --no-headers --selector="kubernetes.io/hostname!=$(get_local_node_name)"
}

function kubernetes_remote_masters() {
    kubectl get nodes --ignore-not-found --no-headers --selector="$(kubernetes_get_control_plane_label),kubernetes.io/hostname!=$(get_local_node_name)"
}

function kubernetes_workers() {
    kubectl get nodes --ignore-not-found --no-headers --selector='!'"$(kubernetes_get_control_plane_label)"
}

function kubernetes_get_control_plane_label() {
    if kubectl get nodes --show-labels | grep -qF "node-role.kubernetes.io/master" ; then
        echo "node-role.kubernetes.io/master"
    else
        echo "node-role.kubernetes.io/control-plane"
    fi
}

# exit 0 if there are any remote workers or masters
function kubernetes_has_remotes() {
    if ! kubernetes_api_is_healthy; then
        # assume this is a new install
        return 1
    fi

    local count=$(kubectl get nodes --ignore-not-found --no-headers --selector="kubernetes.io/hostname!=$(get_local_node_name)" | wc -l)
    if [ "$count" -gt "0" ]; then
        return 0
    fi

    return 1
}

# Fetch the load balancer endpoint from the cluster.
function existing_kubernetes_api_address() {
    kubectl get cm -n kube-system kurl-config -o jsonpath='{ .data.kubernetes_api_address }'
}

# During the upgrade user might change the load balancer endpoint or want to use EKCO internal load balancer. So, we
# to be checking the api endpoint status on the existing api server endpoint as the new endpoint is only available after
# finishing the upgrade.
function kubernetes_api_address() {
    if [ -n "$upgrading_kubernetes" ]; then
        existing_kubernetes_api_address
    else
        local addr="$LOAD_BALANCER_ADDRESS"
        local port="$LOAD_BALANCER_PORT"

        if [ -z "$addr" ]; then
            addr="$PRIVATE_ADDRESS"
            port="6443"
        fi

        addr=$(${DIR}/bin/kurl netutil format-ip-address ${addr})

        echo "${addr}:${port}"
    fi
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
    echo "Waiting for kubernetes api health to report ok"
    for i in {1..10}; do
        sleep 1
        spinner_kubernetes_api_healthy
    done
}

function kubernetes_drain() {
    local deleteEmptydirDataFlag="--delete-emptydir-data"
    local k8sVersion=
    k8sVersion=$(grep ' image: ' /etc/kubernetes/manifests/kube-apiserver.yaml | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    local k8sVersionMinor=
    k8sVersionMinor=$(kubernetes_version_minor "$k8sVersion")
    if [ "$k8sVersionMinor" -lt "20" ]; then
        deleteEmptydirDataFlag="--delete-local-data"
    fi
    # --pod-selector='app!=csi-attacher,app!=csi-provisioner'
    # https://longhorn.io/docs/1.3.2/volumes-and-nodes/maintenance/#updating-the-node-os-or-container-runtime
    if kubernetes_has_remotes ; then
        kubectl drain "$1" \
            "$deleteEmptydirDataFlag" \
            --ignore-daemonsets \
            --force \
            --grace-period=30 \
            --timeout=120s \
            --pod-selector 'app notin (rook-ceph-mon,rook-ceph-osd,rook-ceph-osd-prepare,rook-ceph-operator,rook-ceph-agent),k8s-app!=kube-dns, name notin (restic)' || true
    else
        # On single node installs force drain to delete pods or
        # else the command will timeout when evicting pods with pod disruption budgets
        kubectl drain "$1" \
            "$deleteEmptydirDataFlag" \
            --ignore-daemonsets \
            --force \
            --grace-period=30 \
            --timeout=120s \
            --disable-eviction \
            --pod-selector 'app notin (rook-ceph-mon,rook-ceph-osd,rook-ceph-osd-prepare,rook-ceph-operator,rook-ceph-agent),k8s-app!=kube-dns, name notin (restic)' || true
    fi
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

function kubernetes_scale_down() {
    local ns="$1"
    local kind="$2"
    local name="$3"

    kubernetes_scale "$ns" "$kind" "$name" "0"
}

function kubernetes_scale() {
    local ns="$1"
    local kind="$2"
    local name="$3"
    local replicas="$4"

    if ! kubernetes_resource_exists "$ns" "$kind" "$name"; then
        return 0
    fi

    kubectl -n "$ns" scale "$kind" "$name" --replicas="$replicas"
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
    # TODO check ipv6 cidr for overlaps
    if [ "$IPV6_ONLY" = "1" ]; then
        if [ -z "$POD_CIDR" ]; then
            POD_CIDR="fd00:c00b:1::/112"
        fi
        return 0
    fi

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
        if ! confirmY ; then
            exit 1
        fi
        return 0
    fi
    # detected from weave device
    if [ -n "$EXISTING_POD_CIDR" ]; then
        echo "Using existing pod network ${EXISTING_POD_CIDR}"
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

    if [ -n "$WEAVE_VERSION" ] ; then
        bail "Failed to find an available /${size} subnet for the pod network within either 10.32.0.0/16 or 10.0.0.0/8. \n  Use Weave's podCIDR parameter to set a pod network that is not already in use. \n  https://kurl.sh/docs/add-ons/weave#advanced-install-options"
    else
        bail "Failed to find an available /${size} subnet for the pod network within either 10.32.0.0/16 or 10.0.0.0/8. \n  Use Flannel's podCIDR parameter to set a pod network that is not already in use. \n  https://kurl.sh/docs/add-ons/flannel#advanced-install-options"
    fi
}

# This must run after discover_pod_subnet since it excludes the pod cidr
function discover_service_subnet() {
    # TODO check ipv6 cidr for overlaps
    if [ "$IPV6_ONLY" = "1" ]; then
        if [ -z "$SERVICE_CIDR" ]; then
            SERVICE_CIDR="fd00:c00b:2::/112"
        fi
        return 0
    fi
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
        if ! confirmY ; then
            exit 1
        fi
        return 0
    fi

    if [ -n "$EXISTING_SERVICE_CIDR" ]; then
        echo "Using existing service network ${EXISTING_SERVICE_CIDR}"
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

    bail "Failed to find an available /${size} subnet for the service network within either 10.32.0.0/16 or 10.0.0.0/8. \n  Use Kubernetes's serviceCIDR parameter to set a pod network that is not already in use. \n  https://kurl.sh/docs/add-ons/kubernetes#advanced-install-options"
}

function kubernetes_node_images() {
    local nodeName="$1"

    kubectl get node "$nodeName" -ojsonpath="{range .status.images[*]}{ range .names[*] }{ @ }{'\n'}{ end }{ end }"
}

function list_all_required_images() {
    echo "$KURL_UTIL_IMAGE"

    find packages/kubernetes/$KUBERNETES_VERSION -type f -name Manifest 2>/dev/null | xargs cat | grep -E '^image' | grep -v no_remote_load | awk '{ print $3 }'

    if [ -n "$DOCKER_VERSION" ]; then
        find packages/docker/$DOCKER_VERSION -type f -name Manifest 2>/dev/null | xargs cat | grep -E '^image' | grep -v no_remote_load | awk '{ print $3 }'
    fi

    for dir in addons/*/ ; do
        local addon=
        addon=$(basename "$dir")
        local varname="${addon^^}_VERSION"
        varname="${varname//-/_}"
        local addon_version="${!varname}"
        if [ -z "$addon_version" ]; then
            continue
        fi
        local manifest_file="addons/$addon/$addon_version/Manifest"
        if [ ! -f "$manifest_file" ]; then
            continue
        fi
        grep -E '^image' "$manifest_file" | grep -v no_remote_load | awk '{ print $3 }'
    done
}

function kubernetes_node_has_all_images() {
    local node_name="$1"

    local image_list=
    while read -r image; do
        if ! kubernetes_node_has_image "$node_name" "$image"; then
            image_list="$image_list $image"
        fi
    done < <(list_all_required_images)

    image_list=$(echo "$image_list" | xargs) # strip leading and trailing whitespace

    if [ -n "$image_list" ]; then
        log ""
        logWarn "Node $node_name missing image(s) $image_list"
        return 1
    fi
}

# kubernetes_nodes_missing_images will return a list of nodes that are missing any of the images in
# the provided list
function kubernetes_nodes_missing_images() {
    local images_list="$1"
    local target_host="$2"
    local exclude_hosts="$3"

    if [ -z "$images_list" ]; then
        return
    fi

    # shellcheck disable=SC2086
    "$DIR"/bin/kurl cluster nodes-missing-images --image="$KURL_UTIL_IMAGE" --target-host="$target_host" --exclude-host="$exclude_hosts" $images_list
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
    local primary=
    while read -r primary ; do
        local name=
        name=$(echo "$primary" | awk '{ print $1 }')
        local version=
        version="$(try_1m kubernetes_node_kubelet_version "$name")"

        KUBERNETES_REMOTE_PRIMARIES+=( "$name" )
        KUBERNETES_REMOTE_PRIMARY_VERSIONS+=( "${version#v}" ) # strip leading v
    done < <(kubernetes_remote_masters)
}

KUBERNETES_SECONDARIES=()
KUBERNETES_SECONDARY_VERSIONS=()
function kubernetes_get_secondaries() {
    local secondary=
    while read -r secondary ; do
        local name=
        name=$(echo "$secondary" | awk '{ print $1 }')
        local version=
        version="$(try_1m kubernetes_node_kubelet_version "$name")"

        KUBERNETES_SECONDARIES+=( "$name" )
        KUBERNETES_SECONDARY_VERSIONS+=( "${version#v}" ) # strip leading v
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
    if grep -sq "${api_service_address}" /etc/kubernetes/kubelet.conf ; then
        return 0
    fi
    if grep -sq "${api_service_address}" "$KUBEADM_CONF_FILE" ; then
        return 0
    fi
    return 1
}

function kubernetes_is_join_node() {
    if grep -sq 'kind: JoinConfiguration' "$KUBEADM_CONF_FILE" ; then
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

    if [ -n "$WEAVE_VERSION" ]; then
        log "Checking if weave-net binary can be found in the path /opt/cni/bin/"
        if ! ls -la /opt/cni/bin/ | grep weave-net; then
            logWarn "Unable to find weave-net binary, deleting weave-net pod so that the binary will be recreated"
            kubectl delete pods --selector=name=weave-net --field-selector="spec.nodeName=$(get_local_node_name)" -n kube-system --ignore-not-found=true
        fi
    fi

    if ! kubernetes_any_node_ready; then
        echo "Waiting up to 10 minutes for node to report Ready"
        if ! spinner_until 600 kubernetes_any_node_ready ; then
            # Output the nodes for we know more about the problem
            kubectl get nodes
            bail "Any Node failed to report Ready"
        fi
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
    if ! spinner_until 120 kubernetes_pod_started kurlnet-client default; then
        bail "kurlnet-client pod failed to start"
    fi

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

function kubernetes_all_nodes_ready() {
    local node_statuses=
    node_statuses="$(kubectl get nodes --no-headers 2>/dev/null | awk '{ print $2 }')"
    # no nodes are not ready and at least one node is ready
    if echo "${node_statuses}" | grep -q 'NotReady' && \
            echo "${node_statuses}" | grep -v 'NotReady' | grep -q 'Ready' ; then
        return 1
    fi
    return 0
}

function kubernetes_any_node_ready() {
    if kubectl get nodes --no-headers 2>/dev/null | awk '{ print $2 }' | grep -v 'NotReady' | grep -q 'Ready' ; then
        return 0
    fi
    return 1
}

# Helper function which calculates the amount of the given resource (either CPU or memory)
# to reserve in a given resource range, specified by a start and end of the range and a percentage
# of the resource to reserve. Note that we return zero if the start of the resource range is
# greater than the total resource capacity on the node. Additionally, if the end range exceeds the total
# resource capacity of the node, we use the total resource capacity as the end of the range.
# Args:
#   $1 total available resource on the worker node in input unit (either millicores for CPU or Mi for memory)
#   $2 start of the resource range in input unit
#   $3 end of the resource range in input unit
#   $4 percentage of range to reserve in percent*100 (to allow for two decimal digits)
# Return:
#   amount of resource to reserve in input unit
function get_resource_to_reserve_in_range() {
    local total_resource_on_instance=$1
    local start_range=$2
    local end_range=$3
    local percentage=$4
    resources_to_reserve="0"
    if (( $total_resource_on_instance > $start_range )); then
        resources_to_reserve=$(((($total_resource_on_instance < $end_range ? \
            $total_resource_on_instance : $end_range) - $start_range) * $percentage / 100 / 100))
    fi
    echo $resources_to_reserve
}

# Calculates the amount of memory to reserve for the kubelet in mebibytes from the total memory available on the instance.
# From the total memory capacity of this worker node, we calculate the memory resources to reserve
# by reserving a percentage of the memory in each range up to the total memory available on the instance.
# We are using these memory ranges from GKE (https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-architecture#node_allocatable):
# 255 Mi of memory for machines with less than 1024Mi of memory
# 25% of the first 4096Mi of memory
# 20% of the next 4096Mi of memory (up to 8192Mi)
# 10% of the next 8192Mi of memory (up to 16384Mi)
# 6% of the next 114688Mi of memory (up to 131072Mi)
# 2% of any memory above 131072Mi
# Args:
#   $1 total available memory on the machine in Mi
# Return:
#   memory to reserve in Mi for the kubelet
function get_memory_mebibytes_to_reserve() {
    local total_memory_on_instance=$1
    local memory_ranges=(0 4096 8192 16384 131072 $total_memory_on_instance)
    local memory_percentage_reserved_for_ranges=(2500 2000 1000 600 200)
    if (( $total_memory_on_instance <= 1024 )); then
        memory_to_reserve="255"
    else
        memory_to_reserve="0"
        for i in ${!memory_percentage_reserved_for_ranges[@]}; do
        local start_range=${memory_ranges[$i]}
        local end_range=${memory_ranges[(($i+1))]}
        local percentage_to_reserve_for_range=${memory_percentage_reserved_for_ranges[$i]}
        memory_to_reserve=$(($memory_to_reserve + \
            $(get_resource_to_reserve_in_range $total_memory_on_instance $start_range $end_range $percentage_to_reserve_for_range)))
        done
    fi
    echo $memory_to_reserve
}

# Calculates the amount of CPU to reserve for the kubelet in millicores from the total number of vCPUs available on the instance.
# From the total core capacity of this worker node, we calculate the CPU resources to reserve by reserving a percentage
# of the available cores in each range up to the total number of cores available on the instance.
# We are using these CPU ranges from GKE (https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-architecture#node_allocatable):
# 6% of the first core
# 1% of the next core (up to 2 cores)
# 0.5% of the next 2 cores (up to 4 cores)
# 0.25% of any cores above 4 cores
# Args:
#   $1 total number of millicores on the instance (number of vCPUs * 1000)
# Return:
#   CPU resources to reserve in millicores (m)
function get_cpu_millicores_to_reserve() {
    local total_cpu_on_instance=$1
    local cpu_ranges=(0 1000 2000 4000 $total_cpu_on_instance)
    local cpu_percentage_reserved_for_ranges=(600 100 50 25)
    cpu_to_reserve="0"
    for i in ${!cpu_percentage_reserved_for_ranges[@]}; do
        local start_range=${cpu_ranges[$i]}
        local end_range=${cpu_ranges[(($i+1))]}
        local percentage_to_reserve_for_range=${cpu_percentage_reserved_for_ranges[$i]}
        cpu_to_reserve=$(($cpu_to_reserve + \
            $(get_resource_to_reserve_in_range $total_cpu_on_instance $start_range $end_range $percentage_to_reserve_for_range)))
    done
    echo $cpu_to_reserve
}

function file_exists() {
    local filename=$1

    if ! test -f "$filename"; then
        return 1
    fi
}

# checks if the service in ns $1 with name $2 has endpoints
function kubernetes_service_healthy() {
    local namespace=$1
    local name=$2

    kubectl -n "$namespace" get endpoints "$name" --no-headers | grep -v "<none>" &>/dev/null
}

function kubernetes_version_minor() {
    local k8sVersion="$1"
    # shellcheck disable=SC2001
    echo "$k8sVersion" | sed 's/v\?[0-9]*\.\([0-9]*\)\.[0-9]*/\1/'
}

# kubernetes_configure_pause_image will make kubelet aware of the pause (sandbox) image used by
# containerd. This will prevent the kubelet from garbage collecting the pause image.
# This flag will be removed in kubernetes 1.27.
# NOTE: this configures the kubelet to use the pause image used by containerd rather than the other
# way around.
function kubernetes_configure_pause_image() {
    local dir="$1"
    #shellcheck disable=SC2153
    if [ "$KUBERNETES_TARGET_VERSION_MAJOR" != 1 ] || [ "$KUBERNETES_TARGET_VERSION_MINOR" -ge 27 ]; then
        return
    fi

    local CONTAINERD_PAUSE_IMAGE=
    #shellcheck disable=SC2034
    CONTAINERD_PAUSE_IMAGE="$(kubernetes_containerd_pause_image)"
    if [ -z "$CONTAINERD_PAUSE_IMAGE" ]; then
        return
    fi

    insert_patches_strategic_merge "$dir/kustomization.yaml" "kubelet-args-pause-image.patch.yaml"
    render_yaml_file_2 "$dir/kubelet-args-pause-image.patch.tmpl.yaml" > "$dir/kubelet-args-pause-image.patch.yaml"

    # templatize the kubeadm version field as this will be rendered (again) when generating the final kubeadm conf file
    # shellcheck disable=SC2016
    sed -i 's|kubeadm.k8s.io/v1beta.*|kubeadm.k8s.io/$(kubeadm_conf_api_version)|' "$dir/kubelet-args-pause-image.patch.yaml"
}

KUBELET_FLAGS_FILE="/var/lib/kubelet/kubeadm-flags.env"

# KURL_HOSTNAME_OVERRIDE can be used to override the node name used by kURL
KURL_HOSTNAME_OVERRIDE=${KURL_HOSTNAME_OVERRIDE:-}

# kubernetes_init_hostname sets the HOSTNAME variable to equal the hostname binary output. If
# KURL_HOSTNAME_OVERRIDE is set, it will be used instead. Otherwise, if the kubelet flags file
# contains a --hostname-override flag, it will be used instead.
function kubernetes_init_hostname() {
    export HOSTNAME
    if [ -n "$KURL_HOSTNAME_OVERRIDE" ]; then
        HOSTNAME="$KURL_HOSTNAME_OVERRIDE"
    fi
    local hostname_override=
    hostname_override="$(kubernetes_get_kubelet_hostname_override)"
    if [ -n "$hostname_override" ] ; then
        HOSTNAME="$hostname_override"
    fi
    HOSTNAME="$(hostname | tr '[:upper:]' '[:lower:]')"
}

# kubernetes_get_kubelet_hostname_override returns the value of the --hostname-override flag in the
# kubelet env flags file.
function kubernetes_get_kubelet_hostname_override() {
    if [ -f "$KUBELET_FLAGS_FILE" ]; then
        grep -o '\--hostname-override=[^" ]*' "$KUBELET_FLAGS_FILE" | awk -F'=' '{ print $2 }'
    fi
}

# kubernetes_configure_pause_image_upgrade will check if the pause image used by containerd has
# changed. If it has, it will update the kubelet flags to use the new pause image and restart the
# kubelet.
function kubernetes_configure_pause_image_upgrade() {
    local CONTAINERD_PAUSE_IMAGE=
    #shellcheck disable=SC2034
    CONTAINERD_PAUSE_IMAGE="$(kubernetes_containerd_pause_image)"
    if [ -z "$CONTAINERD_PAUSE_IMAGE" ]; then
        return
    fi

    if [ ! -f "$KUBELET_FLAGS_FILE" ]; then
        return
    fi

    local old_pause_image=
    old_pause_image="$(grep -o '\--pod-infra-container-image=[^" ]*' "$KUBELET_FLAGS_FILE" | awk -F'=' '{ print $2 }')"

    # if the pause image is not set this may be a version of kubelet that does not support the flag
    if [ -z "$old_pause_image" ] || [ "$old_pause_image" = "$CONTAINERD_PAUSE_IMAGE" ]; then
        return
    fi

    sed -i "s|$old_pause_image|$CONTAINERD_PAUSE_IMAGE|" "$KUBELET_FLAGS_FILE"

    systemctl daemon-reload
    systemctl restart kubelet
}

# kubernetes_containerd_pause_image will return the pause image used by containerd.
function kubernetes_containerd_pause_image() {
    if [ -z "$CONTAINERD_VERSION" ] || [ ! -f /etc/containerd/config.toml ] ; then
        return
    fi
    grep sandbox_image /etc/containerd/config.toml | sed 's/[=\"]//g' | awk '{ print $2 }'
}

# kubernetes_kustomize_config_migrate fixes missing and deprecated fields in kustomization file
function kubernetes_kustomize_config_migrate() {
    local kustomize_dir=$1
    if [ "$KUBERNETES_TARGET_VERSION_MINOR" -ge "27" ]; then
        # TODO: Currently this is using kustomize 3.5.4 to migrate the config due to a bug in
        # kustomize v5: https://github.com/kubernetes-sigs/kustomize/issues/5149
       ( cd "$kustomize_dir" && kustomize edit fix )
    fi
}

# kubernetes_configure_coredns is a workaround to reset the custom nameserver config in the coredns
# configmap. This runs after kubeadm init or upgrade which will reset the coredns configmap if it
# finds that it is the default. the issue is that it does a fuzzy match and if only the nameserver
# is set kubeadm determines that it is the default and it replaces the configmap.
function kubernetes_configure_coredns() {
    if [ -z "$NAMESERVER" ]; then
        return 0
    fi
    kubectl -n kube-system get configmap coredns -oyaml > /tmp/Corefile
    # Example lines to replace from k8s 1.17 and 1.19
    # "forward . /etc/resolv.conf" => "forward . 8.8.8.8"
    # "forward . /etc/resolv.conf {" => "forward . 8.8.8.8 {"
    sed -i "s/forward \. \/etc\/resolv\.conf/forward \. ${NAMESERVER}/" /tmp/Corefile
    kubectl -n kube-system replace configmap coredns -f /tmp/Corefile
    kubectl -n kube-system rollout restart deployment/coredns
}
