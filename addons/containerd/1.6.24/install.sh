# shellcheck disable=SC2148

CONTAINERD_NEEDS_RESTART=0
CONTAINERD_DID_MIGRATE_FROM_DOCKER=0

function containerd_pre_init() {
    local src="$DIR/addons/containerd/$CONTAINERD_VERSION"

    # Explicitly configure kubelet to use containerd instead of detecting dockershim socket
    if [ -d "$DIR/kustomize/kubeadm/init-patches" ]; then
        cp "$src/kubeadm-init-config-v1beta2.yaml" "$DIR/kustomize/kubeadm/init-patches/containerd-kubeadm-init-config-v1beta2.yml"
    fi

    containerd_host_init
}

function containerd_join() {
    local src="$DIR/addons/containerd/$CONTAINERD_VERSION"

    # Explicitly configure kubelet to use containerd instead of detecting dockershim socket
    if [ -d "$DIR/kustomize/kubeadm/join-patches" ]; then
        cp "$src/kubeadm-join-config-v1beta2.yaml" "$DIR/kustomize/kubeadm/join-patches/containerd-kubeadm-join-config-v1beta2.yml"
    fi

    containerd_host_init
}

function containerd_install() {
    local src="$DIR/addons/containerd/$CONTAINERD_VERSION"

    if ! containerd_xfs_ftype_enabled; then
        bail "The filesystem mounted at /var/lib/containerd does not have ftype enabled"
    fi

    containerd_migrate_from_docker

    install_host_packages "$src" containerd.io

    chmod +x ${DIR}/addons/containerd/${CONTAINERD_VERSION}/assets/runc
    # If the runc binary is executing the cp command will fail with "text file busy" error.
    # Containerd uses runc in detached mode so any runc processes should be short-lived and exit
    # as soon as the container starts
    try_1m_stderr cp ${DIR}/addons/containerd/${CONTAINERD_VERSION}/assets/runc $(which runc)

    logStep "Containerd configuration"
    containerd_configure

    log "Enabling containerd"
    systemctl enable containerd

    log "Enabling containerd crictl"
    containerd_configure_ctl "$src"

    log "Checking for containerd custom settings"
    containerd_configure_limitnofile

    # NOTE: this will not remove the proxy
    log "Checking for proxy set"
    if [ -n "$PROXY_ADDRESS" ]; then
        log "Proxy is set with the value: ($PROXY_ADDRESS)"
        containerd_configure_proxy
    fi

    log "Checking registry configuration for the distro ${K8S_DISTRO} and if Docker registry IP is set"
    if commandExists ${K8S_DISTRO}_registry_containerd_configure && [ -n "$DOCKER_REGISTRY_IP" ]; then
        log "Docker registry IP is set with the value: ($DOCKER_REGISTRY_IP)"
        ${K8S_DISTRO}_registry_containerd_configure "$DOCKER_REGISTRY_IP"
        CONTAINERD_NEEDS_RESTART=1
    fi

    log "Checking if containerd requires to be re-started"
    if [ "$CONTAINERD_NEEDS_RESTART" = "1" ]; then
        log "Re-starting containerd"
        systemctl daemon-reload
        if ! restart_systemd_and_wait containerd; then
            log "containerd status"
            systemctl status containerd.service
            log "containerd logs"
            journalctl -u containerd.service
            bail "Failed to restart containerd"
        fi
        CONTAINERD_NEEDS_RESTART=0
    fi

    logSuccess "Containerd is successfully configured"

    log "Checking if is required to migrate images from Docker"
    if [ "$AIRGAP" = "1" ] && [ "$CONTAINERD_DID_MIGRATE_FROM_DOCKER" = "1" ]; then
        logStep "Migrating images from Docker to Containerd..."
        containerd_migrate_images_from_docker
        logSuccess "Images migrated successfully"
    fi

    load_images $src/images

    log "Checking if the kubelet service is enabled"
    if systemctl list-unit-files | grep -v disabled | grep -q kubelet.service ; then
        # do not try to start and wait for the kubelet if it is not yet configured
        if [ -f /etc/kubernetes/kubelet.conf ]; then
            log "Starting kubectl"
            systemctl start kubelet
            # If using the internal load balancer the Kubernetes API server will be unavailable until
            # kubelet starts the HAProxy static pod. This check ensures the Kubernetes API server
            # is available before proceeeding.
            # "nodes.v1." is needed becasue addons can have a CRD names "nodes", like nodes.longhorn.io
            try_5m kubectl --kubeconfig=/etc/kubernetes/kubelet.conf get nodes.v1.
        fi
    fi
}

function containerd_host_init() {
    containerd_install_libzstd_if_missing
}

function containerd_install_libzstd_if_missing() {
    local src="$DIR/addons/containerd/$CONTAINERD_VERSION"

    case "$LSB_DIST" in
        centos|rhel|ol|rocky|amzn)
            if yum_is_host_package_installed libzstd ; then
                return
            fi

            if is_rhel_9_variant ; then
                yum_ensure_host_package libzstd
            else
                yum_install_host_archives "$src" libzstd
            fi
            ;;
    esac
}

function containerd_configure() {
    if [ "$CONTAINERD_PRESERVE_CONFIG" = "1" ]; then
        echo "Skipping containerd configuration in order to preserve config."
        return
    fi
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml

    sed -i '/systemd_cgroup/d' /etc/containerd/config.toml
    sed -i '/containerd.runtimes.runc.options/d' /etc/containerd/config.toml
    sed -i 's/level = ""/level = "warn"/' /etc/containerd/config.toml
    cat >> /etc/containerd/config.toml <<EOF
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
  SystemdCgroup = true
EOF
    local pause_image=
    pause_image="$(containerd_kubernetes_pause_image "$KUBERNETES_VERSION")"
    if [ -n "$pause_image" ]; then
        cat >> /etc/containerd/config.toml <<EOF
[plugins."io.containerd.grpc.v1.cri"]
  sandbox_image = "$pause_image"
EOF
        echo "Set containerd sandbox_image to $pause_image"
        cat /etc/containerd/config.toml
    fi

    if [ -n "$CONTAINERD_TOML_CONFIG" ]; then
        log "Found Containerd TomlConfig set. Installer will patch the value $CONTAINERD_TOML_CONFIG"
        local tmp=$(mktemp)
        echo "$CONTAINERD_TOML_CONFIG" > "$tmp"
        "$DIR/bin/toml" -basefile=/etc/containerd/config.toml -patchfile="$tmp"
    fi

    CONTAINERD_NEEDS_RESTART=1
}

function containerd_configure_ctl() {
    local src="$1"

    log "Checks if the file /etc/crictl.yaml exist"
    if [ -e "/etc/crictl.yaml" ]; then
        log "Found /etc/crictl.yaml"
        return 0
    fi

    log "Creates /etc/crictl.yaml"
    cp "$src/crictl.yaml" /etc/crictl.yaml
}

# ceph mon fails liveness on rhel 9 and variants without this setting
# https://github.com/rook/rook/issues/10110
# https://github.com/coreos/fedora-coreos-tracker/issues/329
function containerd_configure_limitnofile() {
    local file=/etc/systemd/system/containerd.service.d/override-limitnofile.conf

    if [ -f "$file" ]; then
        log "Found /etc/systemd/system/containerd.service.d/override-limitnofile.conf"
        return
    fi

    log "Creating /etc/systemd/system/containerd.service.d"
    mkdir -p /etc/systemd/system/containerd.service.d

    echo "# Generated by kURL" > "$file"
    echo "[Service]" >> "$file"
    echo "LimitNOFILE=1048576" >> "$file"
}

function containerd_configure_proxy() {
    log "Configuring containerd proxy"
    local previous_http_proxy="$(cat /etc/systemd/system/containerd.service.d/http-proxy.conf 2>/dev/null | grep -io 'http_proxy=[^\" ]*' | awk 'BEGIN { FS="=" }; { print $2 }')"
    local previous_https_proxy="$(cat /etc/systemd/system/containerd.service.d/http-proxy.conf 2>/dev/null | grep -io 'https_proxy=[^\" ]*' | awk 'BEGIN { FS="=" }; { print $2 }')"
    local previous_no_proxy="$(cat /etc/systemd/system/containerd.service.d/http-proxy.conf 2>/dev/null | grep -io 'no_proxy=[^\" ]*' | awk 'BEGIN { FS="=" }; { print $2 }')"
    log "Previous http proxy: ($previous_http_proxy)"
    log "Previous https proxy: ($previous_https_proxy)"
    log "Previous no proxy: ($previous_no_proxy)"
    if [ "$PROXY_ADDRESS" = "$previous_proxy" ] && [ "$PROXY_HTTPS_ADDRESS" = "$previous_https_proxy" ] && [ "$NO_PROXY_ADDRESSES" = "$previous_no_proxy" ]; then
        log "No changes were found. Proxy configuration still the same"
        return
    fi

    log "Updating proxy configuration: HTTP_PROXY=${PROXY_ADDRESS} NO_PROXY=${NO_PROXY_ADDRESSES}"
    mkdir -p /etc/systemd/system/containerd.service.d
    local file=/etc/systemd/system/containerd.service.d/http-proxy.conf

    echo "# Generated by kURL" > $file
    echo "[Service]" >> $file

    echo "Environment=\"HTTP_PROXY=${PROXY_ADDRESS}\" \"HTTPS_PROXY=${PROXY_HTTPS_ADDRESS}\" \"NO_PROXY=${NO_PROXY_ADDRESSES}\"" >> $file


    CONTAINERD_NEEDS_RESTART=1
}

# Returns 0 on non-xfs filesystems and on xfs filesystems if ftype=1.
function containerd_xfs_ftype_enabled() {
    if ! commandExists xfs_info; then
        return 0
    fi

    mkdir -p /var/lib/containerd

    if xfs_info /var/lib/containerd 2>/dev/null | grep -q "ftype=0"; then
        return 1
    fi

    return 0
}

function containerd_migrate_from_docker() {
    if ! commandExists docker; then
        return
    fi

    if ! commandExists kubectl; then
        return
    fi

    local kubeconfigFlag="--kubeconfig=/etc/kubernetes/kubelet.conf"

    if ! kubectl "$kubeconfigFlag" get node "$(get_local_node_name)" -o jsonpath='{.status.nodeInfo.containerRuntimeVersion}' 2>/dev/null | grep -q docker ; then
        return
    fi

    # steps from https://kubernetes.io/docs/tasks/administer-cluster/migrating-from-dockershim/change-runtime-containerd/

    echo "Draining node to prepare for migration from docker to containerd"

    # Delete pods that depend on other pods on the same node
    if [ -f "$DIR/addons/ekco/$EKCO_VERSION/reboot/shutdown.sh" ]; then
        bash $DIR/addons/ekco/$EKCO_VERSION/reboot/shutdown.sh
    elif [ -f /opt/ekco/shutdown.sh ]; then
        bash /opt/ekco/shutdown.sh
    else
        logFail "EKCO shutdown script not available. Migration to containerd may fail\n"
        if ! confirmN ; then
            bail "Migration to Containerd has been aborted."
        fi
    fi

    echo "Cordoning node"

    local node=
    node="$(get_local_node_name)"
    kubectl "$kubeconfigFlag" cordon "$node" 

    echo "Deleting pods"
    local allPodUIDs=$(kubectl "$kubeconfigFlag" get pods --all-namespaces -ojsonpath='{ range .items[*]}{.metadata.name}{"\t"}{.metadata.uid}{"\t"}{.metadata.namespace}{"\n"}{end}')

    # Drain remaining pods using only the permissions available to kubelet
    while read -r uid; do
        local pod=$(echo "${allPodUIDs[*]}" | grep "$uid")
        if [ -z "$pod" ]; then
            continue
        fi
        local podName=$(echo "$pod" | awk '{ print $1 }')
        local podNamespace=$(echo "$pod" | awk '{ print $3 }')
        # some may timeout but proceed anyway
        kubectl "$kubeconfigFlag" delete pod "$podName" --namespace="$podNamespace" --timeout=60s || true
    done < <(ls /var/lib/kubelet/pods)

    echo "Stopping kubelet"
    systemctl stop kubelet

    if kubectl "$kubeconfigFlag" get node "$node" -ojsonpath='{.metadata.annotations.kubeadm\.alpha\.kubernetes\.io/cri-socket}' | grep -q "dockershim.sock" ; then
        kubectl "$kubeconfigFlag" annotate node "$node" --overwrite "kubeadm.alpha.kubernetes.io/cri-socket=unix:///run/containerd/containerd.sock"
    fi

    if [ "$(docker ps -aq | wc -l)" != "0" ] ; then
        docker ps -aq | xargs docker rm -f || true
    fi

    # Reconfigure kubelet to use containerd
    containerdFlags="--container-runtime=remote --container-runtime-endpoint=unix:///run/containerd/containerd.sock"
    sed -i "s@\(KUBELET_KUBEADM_ARGS=\".*\)\"@\1 $containerdFlags\" @" /var/lib/kubelet/kubeadm-flags.env

    systemctl daemon-reload

    echo "Migrated to containerd"
    CONTAINERD_DID_MIGRATE_FROM_DOCKER=1
}

function containerd_can_migrate_images_from_docker() {
    local images_kb="$(du -sc /var/lib/docker/overlay2 | grep total | awk '{print $1}')"
    local available_kb="$(df --output=avail /var/lib/containerd/ | awk 'NR > 1')"

    if [ -z "$images_kb" ]; then
        logWarn "Unable to determine size of Docker images"
        return 0
    elif [ -z "$available_kb" ]; then
        logWarn "Unable to determine available disk space in /var/lib/containerd/"
        return 0
    else
        local images_kb_x2="$(expr $images_kb + $images_kb)"
        if [ "$available_kb" -lt "$images_kb_x2" ]; then
            local images_human="$(echo "$images_kb" | awk '{print int($1/1024/1024+0.5) "GB"}')"
            local available_human="$(echo "$available_kb" | awk '{print int($1/1024/1024+0.5) "GB"}')"
            logFail "There is not enough available disk space (${available_human}) to migrate images (${images_human}) from Docker to Containerd."
            logFail "Please make sure there is at least 2 x size of Docker images available disk space."
            return 1
        fi
    fi
    return 0
}

function containerd_migrate_images_from_docker() {
    if ! containerd_can_migrate_images_from_docker ; then
        exit 1
    fi

    # we must always clean up $tmpdir since it can take up a lot of space
    local errcode=0
    local tmpdir="$(mktemp -d -p /var/lib/containerd)"
    _containerd_migrate_images_from_docker "$tmpdir" || errcode="$?"
    rm -rf "$tmpdir"
    return "$errcode"
}

function _containerd_migrate_images_from_docker() {
    local tmpdir="$1"
    local imagefile=
    for image in $(docker images --format '{{.Repository}}:{{.Tag}}' | grep -v '^<none>'); do
        imagefile="${tmpdir}/$(echo $image | tr -cd '[:alnum:]').tar"
        (set -x; docker save $image -o "$imagefile")
    done
    for image in $tmpdir/* ; do
        (set -x; ctr -n=k8s.io images import $image)
    done
}

# return the pause image for the specified minor version of kubernetes
# versions 1.26 and earlier return the empty string as they can be overridden to use a different image
function containerd_kubernetes_pause_image() {
    version="$1"
    local minor_version=
    minor_version="$(kubernetes_version_minor "$version")"

    if [ "$minor_version" -gt "27" ]; then
        echo "registry.k8s.io/pause:3.9"
    else
        echo ""
    fi
}
