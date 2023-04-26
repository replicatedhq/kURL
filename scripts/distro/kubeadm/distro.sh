
function kubeadm_discover_private_ip() {
    local private_address

    private_address="$(grep 'advertise-address' /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null | awk -F'=' '{ print $2 }')"

    # This is needed on k8s 1.18.x as $PRIVATE_ADDRESS is found to have a newline
    echo "${private_address}" | tr -d '\n'
}

function kubeadm_get_kubeconfig() {
    echo "/etc/kubernetes/admin.conf"
}

function kubeadm_get_containerd_sock() {
    echo "/run/containerd/containerd.sock"
}

function kubeadm_get_client_kube_apiserver_crt() {
    echo "/etc/kubernetes/pki/apiserver-kubelet-client.crt"
}

function kubeadm_get_client_kube_apiserver_key() {
    echo "/etc/kubernetes/pki/apiserver-kubelet-client.key"
}

function kubeadm_get_server_ca() {
    echo "/etc/kubernetes/pki/ca.crt"
}

function kubeadm_get_server_ca_key() {
    echo "/etc/kubernetes/pki/ca.key"
}

function kubeadm_addon_for_each() {
    local cmd="$1"

    if [ "$cmd" != "addon_install" ]; then # this is run in install_cri
        $cmd containerd "$CONTAINERD_VERSION" "$CONTAINERD_S3_OVERRIDE"
    fi
    $cmd aws "$AWS_VERSION"
    $cmd nodeless "$NODELESS_VERSION"
    $cmd calico "$CALICO_VERSION" "$CALICO_S3_OVERRIDE"
    $cmd weave "$WEAVE_VERSION" "$WEAVE_S3_OVERRIDE"
    $cmd flannel "$FLANNEL_VERSION" "$FLANNEL_S3_OVERRIDE"
    $cmd antrea "$ANTREA_VERSION" "$ANTREA_S3_OVERRIDE"
    $cmd rook "$ROOK_VERSION" "$ROOK_S3_OVERRIDE"
    $cmd ekco "$EKCO_VERSION" "$EKCO_S3_OVERRIDE"
    $cmd openebs "$OPENEBS_VERSION" "$OPENEBS_S3_OVERRIDE"
    $cmd longhorn "$LONGHORN_VERSION" "$LONGHORN_S3_OVERRIDE"
    $cmd aws "$AWS_VERSION" "$AWS_S3_OVERRIDE"
    $cmd minio "$MINIO_VERSION" "$MINIO_S3_OVERRIDE"
    $cmd contour "$CONTOUR_VERSION" "$CONTOUR_S3_OVERRIDE"
    $cmd registry "$REGISTRY_VERSION" "$REGISTRY_S3_OVERRIDE"
    $cmd prometheus "$PROMETHEUS_VERSION" "$PROMETHEUS_S3_OVERRIDE"
    $cmd kotsadm "$KOTSADM_VERSION" "$KOTSADM_S3_OVERRIDE"
    $cmd velero "$VELERO_VERSION" "$VELERO_S3_OVERRIDE"
    $cmd fluentd "$FLUENTD_VERSION" "$FLUENTD_S3_OVERRIDE"
    $cmd collectd "$COLLECTD_VERSION" "$COLLECTD_S3_OVERRIDE"
    $cmd cert-manager "$CERT_MANAGER_VERSION" "$CERT_MANAGER_S3_OVERRIDE"
    $cmd metrics-server "$METRICS_SERVER_VERSION" "$METRICS_SERVER_S3_OVERRIDE"
    $cmd sonobuoy "$SONOBUOY_VERSION" "$SONOBUOY_S3_OVERRIDE"
    $cmd goldpinger "$GOLDPINGER_VERSION" "$GOLDPINGER_S3_OVERRIDE"
}

function kubeadm_reset() {
    if [ -z "$WEAVE_TAG" ]; then
        WEAVE_TAG="$(get_weave_version)"
    fi

    if [ -n "$DOCKER_VERSION" ]; then
        kubeadm reset --force
    else
        kubeadm reset --force --cri-socket /var/run/containerd/containerd.sock
    fi
    printf "kubeadm reset completed\n"

    if [ -f /etc/cni/net.d/10-weave.conflist ]; then
        kubeadm_weave_reset
    fi
    printf "weave reset completed\n"
}

function kubeadm_weave_reset() {
    BRIDGE=weave
    DATAPATH=datapath
    CONTAINER_IFNAME=ethwe

    DOCKER_BRIDGE=docker0

    WEAVEEXEC_IMAGE="weaveworks/weaveexec"

    kurlshWeaveVersionPattern='^[0-9]+\.[0-9]+\.[0-9]+(.*)-(20)[0-9]{6}(.*)$'
    if [[ $WEAVE_TAG =~ $kurlshWeaveVersionPattern ]] ; then
        WEAVEEXEC_IMAGE="kurlsh/weaveexec"
    fi

    # https://github.com/weaveworks/weave/blob/v2.8.1/weave#L461
    for NETDEV in $BRIDGE $DATAPATH ; do
        if [ -d /sys/class/net/$NETDEV ] ; then
            if [ -d /sys/class/net/$NETDEV/bridge ] ; then
                ip link del $NETDEV
            else
                if [ -n "$DOCKER_VERSION" ]; then
                    docker run --rm --pid host --net host --privileged --entrypoint=/usr/bin/weaveutil $WEAVEEXEC_IMAGE:$WEAVE_TAG delete-datapath $NETDEV
                else
                    # --pid host
                    local guid=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c16)
                    ctr -n=k8s.io run --rm --net-host --privileged docker.io/$WEAVEEXEC_IMAGE:$WEAVE_TAG $guid /usr/bin/weaveutil delete-datapath $NETDEV
                fi
            fi
        fi
    done

    # Remove any lingering bridged fastdp, pcap and attach-bridge veths
    for VETH in $(ip -o link show | grep -o v${CONTAINER_IFNAME}[^:@]*) ; do
        ip link del $VETH >/dev/null 2>&1 || true
    done

    if [ "$DOCKER_BRIDGE" != "$BRIDGE" ] ; then
        kubeadm_run_iptables -t filter -D FORWARD -i $DOCKER_BRIDGE -o $BRIDGE -j DROP 2>/dev/null || true
    fi

    kubeadm_run_iptables -t filter -D INPUT -d 127.0.0.1/32 -p tcp --dport 6784 -m addrtype ! --src-type LOCAL -m conntrack ! --ctstate RELATED,ESTABLISHED -m comment --comment "Block non-local access to Weave Net control port" -j DROP >/dev/null 2>&1 || true
    kubeadm_run_iptables -t filter -D INPUT -i $DOCKER_BRIDGE -p udp --dport 53  -j ACCEPT  >/dev/null 2>&1 || true
    kubeadm_run_iptables -t filter -D INPUT -i $DOCKER_BRIDGE -p tcp --dport 53  -j ACCEPT  >/dev/null 2>&1 || true

    if [ -n "$DOCKER_VERSION" ]; then
        DOCKER_BRIDGE_IP=$(docker run --rm --pid host --net host --privileged -v /var/run/docker.sock:/var/run/docker.sock --entrypoint=/usr/bin/weaveutil $WEAVEEXEC_IMAGE:$WEAVE_TAG bridge-ip $DOCKER_BRIDGE)

        kubeadm_run_iptables -t filter -D INPUT -i $DOCKER_BRIDGE -p tcp --dst $DOCKER_BRIDGE_IP --dport $PORT          -j DROP >/dev/null 2>&1 || true
        kubeadm_run_iptables -t filter -D INPUT -i $DOCKER_BRIDGE -p udp --dst $DOCKER_BRIDGE_IP --dport $PORT          -j DROP >/dev/null 2>&1 || true
        kubeadm_run_iptables -t filter -D INPUT -i $DOCKER_BRIDGE -p udp --dst $DOCKER_BRIDGE_IP --dport $(($PORT + 1)) -j DROP >/dev/null 2>&1 || true
    fi

    kubeadm_run_iptables -t filter -D FORWARD -i $BRIDGE ! -o $BRIDGE -j ACCEPT 2>/dev/null || true
    kubeadm_run_iptables -t filter -D FORWARD -o $BRIDGE -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    kubeadm_run_iptables -t filter -D FORWARD -i $BRIDGE -o $BRIDGE -j ACCEPT 2>/dev/null || true
    kubeadm_run_iptables -F WEAVE-NPC >/dev/null 2>&1 || true
    kubeadm_run_iptables -t filter -D FORWARD -o $BRIDGE -j WEAVE-NPC 2>/dev/null || true
    kubeadm_run_iptables -t filter -D FORWARD -o $BRIDGE -m state --state NEW -j NFLOG --nflog-group 86 2>/dev/null || true
    kubeadm_run_iptables -t filter -D FORWARD -o $BRIDGE -j DROP 2>/dev/null || true
    kubeadm_run_iptables -X WEAVE-NPC >/dev/null 2>&1 || true

    kubeadm_run_iptables -F WEAVE-EXPOSE >/dev/null 2>&1 || true
    kubeadm_run_iptables -t filter -D FORWARD -o $BRIDGE -j WEAVE-EXPOSE 2>/dev/null || true
    kubeadm_run_iptables -X WEAVE-EXPOSE >/dev/null 2>&1 || true

    kubeadm_run_iptables -t nat -F WEAVE >/dev/null 2>&1 || true
    kubeadm_run_iptables -t nat -D POSTROUTING -j WEAVE >/dev/null 2>&1 || true
    kubeadm_run_iptables -t nat -D POSTROUTING -o $BRIDGE -j ACCEPT >/dev/null 2>&1 || true
    kubeadm_run_iptables -t nat -X WEAVE >/dev/null 2>&1 || true

    for LOCAL_IFNAME in $(ip link show | grep v${CONTAINER_IFNAME}pl | cut -d ' ' -f 2 | tr -d ':') ; do
        ip link del ${LOCAL_IFNAME%@*} >/dev/null 2>&1 || true
    done
}

function kubeadm_run_iptables() {
    # -w is recent addition to iptables
    if [ -z "$CHECKED_IPTABLES_W" ] ; then
        iptables -S -w >/dev/null 2>&1 && IPTABLES_W=-w
        CHECKED_IPTABLES_W=1
    fi

    iptables $IPTABLES_W "$@"
}

function kubeadm_containerd_restart() {
    systemctl restart containerd
}

function kubeadm_registry_containerd_configure() {
    local registry_ip="$1"

    local server="$registry_ip"
    if [ "$IPV6_ONLY" = "1" ]; then
        server="registry.kurl.svc.cluster.local"
        sed -i '/registry\.kurl\.svc\.cluster\.local/d' /etc/hosts
        echo "$registry_ip $server" >> /etc/hosts
    fi

    if grep -Fq "plugins.\"io.containerd.grpc.v1.cri\".registry.configs.\"${server}\".tls" /etc/containerd/config.toml; then
        echo "Registry ${server} TLS already configured for containerd"
        return 0
    fi

    cat >> /etc/containerd/config.toml <<EOF
[plugins."io.containerd.grpc.v1.cri".registry.configs."${server}".tls]
  ca_file = "/etc/kubernetes/pki/ca.crt"
EOF

    CONTAINERD_NEEDS_RESTART=1
}

function kubeadm_api_is_healthy() {
    curl --globoff --noproxy "*" --fail --silent --insecure "https://$(kubernetes_api_address)/healthz" >/dev/null
}

function kubeadm_conf_api_version() {
    
    # Get kubeadm api version from the runtime
    # Enforce the use of kubeadm.k8s.io/v1beta3 api version beginning with Kubernetes 1.26+
    local kubeadm_v1beta3_min_version=
    kubeadm_v1beta3_min_version="26"
    if [ -n "$KUBERNETES_TARGET_VERSION_MINOR" ]; then
        if [ "$KUBERNETES_TARGET_VERSION_MINOR" -ge "$kubeadm_v1beta3_min_version" ]; then
            echo "v1beta3"
        else
            echo "v1beta2"
        fi 
    else
        # ################################ NOTE ########################################## #
        # get the version from an existing cluster when the installer is not run           #
        # i.e. this is meant to handle cases where kubeadm config is patched from tasks.sh #

        semverParse "$(kubeadm version --output=short | sed 's/v//')"
        # shellcheck disable=SC2154
        local kube_current_version_minor="$minor"
        if [ "$kube_current_version_minor" -ge "$kubeadm_v1beta3_min_version" ]; then
            echo "v1beta3"
        else
            echo "v1beta2"
        fi
    fi
}

# kubeadm_customize_config mutates a kubeadm configuration file for Kubernetes compatibility purposes
function kubeadm_customize_config() {
    local kubeadm_patch_config=$1

    # Templatize the api version for kubeadm patches
    # shellcheck disable=SC2016
    sed -i 's|kubeadm.k8s.io/v1beta.*|kubeadm.k8s.io/$(kubeadm_conf_api_version)|' "$kubeadm_patch_config"

    # Kubernetes 1.24 deprecated the '--container-runtime' kubelet argument in 1.24 and removed it in 1.27
    # See: https://kubernetes.io/blog/2023/03/17/upcoming-changes-in-kubernetes-v1-27/#removal-of-container-runtime-command-line-argument
    if [ "$KUBERNETES_TARGET_VERSION_MINOR" -ge "24" ]; then
        # remove kubeletExtraArgs.container-runtime from the containerd kubeadm addon patch
        sed -i '/container-runtime:/d' "$kubeadm_patch_config"
    fi
}
    
