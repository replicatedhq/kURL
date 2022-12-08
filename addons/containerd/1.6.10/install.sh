# shellcheck disable=SC2148

CONTAINERD_NEEDS_RESTART=0
CONTAINERD_DID_MIGRATE_FROM_DOCKER=0

function containerd_pre_init() {
    local src="$DIR/addons/containerd/$CONTAINERD_VERSION"

    # Explicitly configure kubelet to use containerd instead of detecting dockershim socket
    if [ -d "$DIR/kustomize/kubeadm/init-patches" ]; then
        cp "$src/kubeadm-init-config-v1beta2.yaml" "$DIR/kustomize/kubeadm/init-patches/containerd-kubeadm-init-config-v1beta2.yml"
    fi
}

function containerd_join() {
    local src="$DIR/addons/containerd/$CONTAINERD_VERSION"

    # Explicitly configure kubelet to use containerd instead of detecting dockershim socket
    if [ -d "$DIR/kustomize/kubeadm/join-patches" ]; then
        cp "$src/kubeadm-join-config-v1beta2.yaml" "$DIR/kustomize/kubeadm/join-patches/containerd-kubeadm-join-config-v1beta2.yml"
    fi
}

function containerd_install() {
    local src="$DIR/addons/containerd/$CONTAINERD_VERSION"

    if ! containerd_xfs_ftype_enabled; then
        bail "The filesystem mounted at /var/lib/containerd does not have ftype enabled"
    fi

    containerd_migrate_from_docker

    if [ "$CONTAINERD_DID_MIGRATE_FROM_DOCKER" != "1" ]; then
        case "$LSB_DIST" in
            ubuntu)
                # Old versions of docker packages may conflict with containerd.io package
                # https://docs.docker.com/engine/install/ubuntu/#uninstall-old-versions
                apt-get remove docker docker-engine docker.io containerd runc
                ;;
        esac
    fi

    install_host_packages "$src" containerd.io

    case "$LSB_DIST" in
        centos|rhel|amzn|ol)
            yum_install_host_archives "$src" libzstd
            ;;
    esac

    chmod +x ${DIR}/addons/containerd/${CONTAINERD_VERSION}/assets/runc
    # If the runc binary is executing the cp command will fail with "text file busy" error.
    # Containerd uses runc in detached mode so any runc processes should be short-lived and exit
    # as soon as the container starts
    try_1m_stderr cp ${DIR}/addons/containerd/${CONTAINERD_VERSION}/assets/runc $(which runc)

    containerd_configure

    systemctl enable containerd

    containerd_configure_ctl "$src"

    # NOTE: this will not remove the proxy
    if [ -n "$PROXY_ADDRESS" ]; then
        containerd_configure_proxy
    fi

    if commandExists ${K8S_DISTRO}_registry_containerd_configure && [ -n "$DOCKER_REGISTRY_IP" ]; then
        ${K8S_DISTRO}_registry_containerd_configure "$DOCKER_REGISTRY_IP"
        CONTAINERD_NEEDS_RESTART=1
    fi

    if [ "$CONTAINERD_NEEDS_RESTART" = "1" ]; then
        systemctl daemon-reload
        restart_systemd_and_wait containerd
        CONTAINERD_NEEDS_RESTART=0
    fi

    if [ "$AIRGAP" = "1" ] && [ "$CONTAINERD_DID_MIGRATE_FROM_DOCKER" = "1" ]; then
        logStep "Migrating images from Docker to Containerd..."
        containerd_migrate_images_from_docker
        logSuccess "Images migrated successfully"
    fi

    load_images $src/images

    if systemctl list-unit-files | grep -v disabled | grep -q kubelet.service; then
        systemctl start kubelet
        # If using the internal load balancer the Kubernetes API server will be unavailable until
        # kubelet starts the HAProxy static pod. This check ensures the Kubernetes API server
        # is available before proceeeding.
        # "nodes.v1." is needed becasue addons can have a CRD names "nodes", like nodes.longhorn.io
        try_5m kubectl --kubeconfig=/etc/kubernetes/kubelet.conf get nodes.v1.
    fi

    local node=
    node="$(get_local_node_name)"
    # migration from docker to containerd will cordon the node and can leave the node unschedulable
    if is_node_unschedulable "$node" ; then
        # With the internal loadbalancer it may take a minute or two after starting kubelet before
        # kubectl commands work
        try_5m kubectl uncordon "$node" --kubeconfig=/etc/kubernetes/kubelet.conf
    fi
}

function containerd_configure() {
    if [ "$CONTAINERD_PRESERVE_CONFIG" = "1" ]; then
        echo "Skipping containerd configuration"
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

	if [ -n "$CONTAINERD_TOML_CONFIG" ]; then
        local tmp=$(mktemp)
        echo "$CONTAINERD_TOML_CONFIG" > "$tmp"
        "$DIR/bin/toml" -basefile=/etc/containerd/config.toml -patchfile="$tmp"
    fi

    CONTAINERD_NEEDS_RESTART=1
}

function containerd_configure_ctl() {
    local src="$1"

    if [ -e "/etc/crictl.yaml" ]; then
        return 0
    fi

    cp "$src/crictl.yaml" /etc/crictl.yaml
}

containerd_configure_proxy() {
    local previous_proxy="$(cat /etc/systemd/system/containerd.service.d/http-proxy.conf 2>/dev/null | grep -io 'https*_proxy=[^\" ]*' | awk 'BEGIN { FS="=" }; { print $2 }')"
    local previous_no_proxy="$(cat /etc/systemd/system/containerd.service.d/http-proxy.conf 2>/dev/null | grep -io 'no_proxy=[^\" ]*' | awk 'BEGIN { FS="=" }; { print $2 }')"
    if [ "$PROXY_ADDRESS" = "$previous_proxy" ] && [ "$NO_PROXY_ADDRESSES" = "$previous_no_proxy" ]; then
        return
    fi

    mkdir -p /etc/systemd/system/containerd.service.d
    local file=/etc/systemd/system/containerd.service.d/http-proxy.conf

    echo "# Generated by kURL" > $file
    echo "[Service]" >> $file

    echo "Environment=\"HTTP_PROXY=${PROXY_ADDRESS}\" \"HTTPS_PROXY=${PROXY_ADDRESS}\" \"NO_PROXY=${NO_PROXY_ADDRESSES}\"" >> $file

    CONTAINERD_NEEDS_RESTART=1
}

# Returns 0 on non-xfs filesystems and on xfs filesystems if ftype=1.
containerd_xfs_ftype_enabled() {
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

    local node=$(hostname | tr '[:upper:]' '[:lower:]')
    kubectl "$kubeconfigFlag" cordon "$node" 

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

# TODO remove this
function _dpkg_install_host_packages() {
    if [ "${SKIP_SYSTEM_PACKAGE_INSTALL}" == "1" ]; then
        logStep "Skipping installation of host packages: ${packages[*]}"
        return
    fi

    local dir="$1"
    local dir_prefix="$2"
    local packages=("${@:3}")

    logStep "Installing host packages ${packages[*]}"

    local fullpath=
    fullpath="${dir}/ubuntu-${DIST_VERSION}${dir_prefix}"
    if ! test -n "$(shopt -s nullglob; echo "${fullpath}"/*.deb)" ; then
        echo "Will not install host packages ${packages[*]}, no packages found."
        return 0
    fi

    DEBIAN_FRONTEND=noninteractive dpkg --install --force-depends-version --force-confold "${fullpath}"/*.deb

    logSuccess "Host packages ${packages[*]} installed"
}

# TODO remove this
function uninstall_docker() {
    if ! commandExists docker || [ -n "$DOCKER_VERSION" ] || [ -z "$CONTAINERD_VERSION" ]; then
        return
    fi

    logStep "Uninstalling Docker..."

    if [ "$(docker ps -aq | wc -l)" != "0" ] ; then
        docker ps -aq | xargs docker rm -f || true
    fi
    # The rm -rf /var/lib/docker command below may fail with device busy error, so remove as much
    # data as possible now
    docker system prune --all --volumes --force || true

    systemctl disable docker.service --now || true

    case "$LSB_DIST" in
        ubuntu)
            export DEBIAN_FRONTEND=noninteractive
            dpkg --purge docker.io docker-ce docker-ce-cli
            ;;

        centos|rhel|amzn|ol)
            local dockerPackages=("docker-ce" "docker-ce-cli")
            if rpm -qa | grep -q 'docker-ce-rootless-extras'; then
                dockerPackages+=("docker-ce-rootless-extras")
            fi
            if rpm -qa | grep -q 'docker-scan-plugin'; then
                dockerPackages+=("docker-scan-plugin")
            fi
            rpm --erase ${dockerPackages[@]}
            ;;
    esac

    rm -rf /var/lib/docker /var/lib/dockershim || true
    rm -f /var/run/dockershim.sock || true
    rm -f /var/run/docker.sock || true

    log "Docker successfully uninstalled."
}

# TODO remove this
function is_node_unschedulable() {
    local node=$1
    [ "$(kubectl get node "$node" -o jsonpath='{.spec.unschedulable}')" = "true" ]
}
