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
    if use_os_containerd; then
        require_os_containerd
        log "Using containerd version provided by the Operating System."
        if ! systemctl is-active --quiet containerd; then
            systemctl start containerd
        fi
    fi

    local src="$DIR/addons/containerd/$CONTAINERD_VERSION"

    if ! containerd_xfs_ftype_enabled; then
        bail "The filesystem mounted at /var/lib/containerd does not have ftype enabled"
    fi

    if ! use_os_containerd; then
        containerd_migrate_from_docker
        containerd_install_container_selinux_if_missing
        install_host_packages "$src" containerd.io
        chmod +x ${DIR}/addons/containerd/${CONTAINERD_VERSION}/assets/runc
        # If the runc binary is executing the cp command will fail with "text file busy" error.
        # Containerd uses runc in detached mode so any runc processes should be short-lived and exit
        # as soon as the container starts
        try_1m_stderr cp ${DIR}/addons/containerd/${CONTAINERD_VERSION}/assets/runc $(which runc)
    fi

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
        restart_systemd_and_wait containerd
        CONTAINERD_NEEDS_RESTART=0
    fi

    logSuccess "Containerd is successfully configured"

    log "Checking if it is required to migrate images from Docker"
    if [ "$AIRGAP" = "1" ] && [ "$CONTAINERD_DID_MIGRATE_FROM_DOCKER" = "1" ]; then
        logStep "Migrating images from Docker to Containerd..."
        containerd_migrate_images_from_docker
        logSuccess "Images migrated successfully"
    else
        log "Migration of images from Docker to Containerd is not required"
    fi

    logStep "Loading images into containerd"
    load_images $src/images
    logSuccess "Images loaded successfully"

    log "Checking if the kubelet service is enabled"
    if systemctl list-unit-files | grep -v disabled | grep -q kubelet.service ; then
        # do not try to start and wait for the kubelet if it is not yet configured
        if [ -f /etc/kubernetes/kubelet.conf ]; then
            log "Starting kubectl"
            systemctl start kubelet
            # If using the internal load balancer the Kubernetes API server will be unavailable until
            # kubelet starts the HAProxy static pod. This check ensures the Kubernetes API server
            # is available before proceeding.
            # "nodes.v1." is needed because addons can have a CRD names "nodes", like nodes.longhorn.io
            # we get the specific node name because as of kubernetes 1.32 the node kubeconfig only has permissions to get the current node
            try_5m kubectl --kubeconfig=/etc/kubernetes/kubelet.conf get nodes.v1. "$(get_local_node_name)"
        fi
    fi
}

function containerd_host_init() {
    require_centos8_containerd
    require_os_containerd
    containerd_install_libzstd_if_missing
}

function containerd_install_libzstd_if_missing() {
    local src="$DIR/addons/containerd/$CONTAINERD_VERSION"

    if ! host_packages_shipped ; then
        ensure_host_package libzstd skip
        return
    fi

    case "$LSB_DIST" in
        centos|rhel|ol|rocky|amzn)
            if yum_is_host_package_installed libzstd ; then
                return
            fi
            yum_install_host_archives "$src" libzstd
            ;;
    esac
}

# install container-selinux independently of containerd.io on centos/rhel/ol 7
function containerd_install_container_selinux_if_missing() {
    local src="$DIR/addons/containerd/$CONTAINERD_VERSION"

    if [ "$DIST_VERSION_MAJOR" != "7" ]; then
        return
    fi

    case "$LSB_DIST" in
        centos|rhel|ol)
            if yum_is_host_package_installed container-selinux ; then
                return
            fi
            yum_install_host_archives "$src" container-selinux
            ;;
    esac
}

# containerd_configure_schema_v2 applies 1.x-specific patches to /etc/containerd/config.toml
# (config schema version = 2). Called by containerd_configure() after schema version detection.
function containerd_configure_schema_v2() {
    local pause_image="$1"

    sed -i 's/level = ""/level = "warn"/' /etc/containerd/config.toml
    # Ensure containerd reads per-registry hosts.toml files
    sed -i 's|config_path = ""|config_path = "/etc/containerd/certs.d"|' /etc/containerd/config.toml

    # Remove stale legacy systemd_cgroup and runc.options lines before appending the correct block.
    sed -i '/systemd_cgroup/d' /etc/containerd/config.toml
    sed -i '/containerd.runtimes.runc.options/d' /etc/containerd/config.toml

    cat >> /etc/containerd/config.toml <<'EOF'
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
  SystemdCgroup = true
EOF

    if [ -n "$pause_image" ]; then
        # replace the line 'sandbox_image = "whatever the image previously was"' with 'sandbox_image = "$pause_image"'
        sed -i "/sandbox_image/c\\    sandbox_image = \"$pause_image\"" /etc/containerd/config.toml
        log "Set containerd sandbox_image to $pause_image"
    fi

    if is_ubuntu_2404; then
        # we need to disable apparmor on ubuntu 24.04 to allow pods to be deleted
        sed -i 's/disable_apparmor = false/disable_apparmor = true/' /etc/containerd/config.toml
    fi
}

# containerd_configure_schema_v3 configures containerd 2.x by writing a drop-in override file.
# (config schema version = 3). Called by containerd_configure() after schema version detection.
# In 2.x the CRI plugin was split: runtime config → io.containerd.cri.v1.runtime,
# image config → io.containerd.cri.v1.images.
# See https://github.com/containerd/containerd/blob/main/docs/cri/config.md
function containerd_configure_schema_v3() {
    local pause_image="$1"

    mkdir -p /etc/containerd/conf.d

    # containerd does not load conf.d drop-ins on its own: `config default` emits
    # imports = [] (verified against upstream 2.0.5 and 2.1.0 binaries). Point imports
    # at conf.d so the drop-in written below takes effect.
    sed -i "s|imports = \[\]|imports = ['/etc/containerd/conf.d/*.toml']|" /etc/containerd/config.toml

    # Single-quoted TOML keys required: containerd 2.x config default uses single-quote delimiters.
    # config_path override eliminates the colon-separated default that io.containerd.transfer.v1.local
    # silently ignores, never reading hosts.toml as a result.
    # https://github.com/containerd/containerd/issues/12415
    # Drop-in filename ordering convention: containerd merges conf.d/*.toml in sorted
    # filename order, later files winning (verified against 2.0.5/2.1.0). kURL defaults use
    # the 50- prefix; user CONTAINERD_TOML_CONFIG is written to 99-user.toml so it merges last
    # and wins. The 51-98 range is reserved headroom for future kURL-managed drop-ins.
    cat > /etc/containerd/conf.d/50-replicated.toml <<'EOF'
version = 3

[debug]
  level = "warn"

[plugins.'io.containerd.transfer.v1.local']
  config_path = '/etc/containerd/certs.d'

[plugins.'io.containerd.cri.v1.images'.registry]
  config_path = '/etc/containerd/certs.d'

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
  SystemdCgroup = true
EOF

    if is_ubuntu_2404; then
        # we need to disable apparmor on ubuntu 24.04 to allow pods to be deleted
        cat >> /etc/containerd/conf.d/50-replicated.toml <<'EOF'

[plugins.'io.containerd.cri.v1.runtime']
  disable_apparmor = true
EOF
    fi

    if [ -n "$pause_image" ]; then
        # Unquoted heredoc: $pause_image must expand. Heredoc append avoids
        # sed escaping issues with '/' or other special chars in image refs.
        cat >> /etc/containerd/conf.d/50-replicated.toml <<EOF

[plugins.'io.containerd.cri.v1.images'.pinned_images]
  sandbox = '$pause_image'
EOF
        log "Set containerd 2.x pinned sandbox image to $pause_image"
    fi
    # The merged config is validated by containerd_configure() after CONTAINERD_TOML_CONFIG
    # patching, so user patches that break the conf.d import are caught too.
}

function containerd_configure() {
    if [ "$CONTAINERD_PRESERVE_CONFIG" = "1" ]; then
        log "Skipping containerd configuration in order to preserve config."
        return
    fi
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml

    # Read the config schema version from the generated file.
    # version = 2 → containerd 1.x; version = 3 → containerd 2.x.
    # Reading the header (not $CONTAINERD_VERSION) is reliable when use_os_containerd() is true.
    local config_schema_version
    config_schema_version=$(awk -F'=' '/^[[:space:]]*version[[:space:]]*=/{gsub(/[[:space:]]/, "", $2); print $2; exit}' /etc/containerd/config.toml)

    local pause_image=
    pause_image="$(containerd_kubernetes_pause_image)"

    if [ "${config_schema_version:-2}" -ge "3" ]; then
        containerd_configure_schema_v3 "$pause_image"
    else
        containerd_configure_schema_v2 "$pause_image"
    fi

    # if containerd is running, this is an upgrade and we can load the pause image
    if [ -n "$pause_image" ] && systemctl is-active --quiet containerd; then
        log "Loading Kubernetes $KUBERNETES_VERSION pause image"
        cat "$DIR/packages/kubernetes/$KUBERNETES_VERSION/images/pause.tar.gz" | gunzip | ctr -n=k8s.io images import -
        log "Loaded Kubernetes $KUBERNETES_VERSION pause image"
    fi

    if [ -n "$CONTAINERD_TOML_CONFIG" ]; then
        if [ "${config_schema_version:-2}" -ge "3" ]; then
            # 2.x: write the user TOML verbatim to a higher-numbered conf.d drop-in. containerd's
            # own import merge (later filename wins) places these keys above kURL's
            # 50-replicated defaults, restoring the 1.x "user patch wins" contract. A version
            # header is not required — version-less fragments merge cleanly (verified on
            # 2.0.5/2.1.0) — so the value is written as-is with no injection or key rewriting.
            local user_dropin=/etc/containerd/conf.d/99-user.toml
            log "Found Containerd TomlConfig set. Writing user overrides to $user_dropin"
            echo "$CONTAINERD_TOML_CONFIG" > "$user_dropin"
        else
            # 1.x: unchanged — leaf-merge the user TOML into the single config.toml via bin/toml.
            log "Found Containerd TomlConfig set. Installer will patch the value $CONTAINERD_TOML_CONFIG"
            local tmp=$(mktemp)
            echo "$CONTAINERD_TOML_CONFIG" > "$tmp"
            "$DIR/bin/toml" -basefile=/etc/containerd/config.toml -patchfile="$tmp"
        fi
    fi

    if [ -n "$CONTAINERD_TOML_CONFIG" ] && [ "${config_schema_version:-2}" -ge "3" ]; then
        logWarn "CONTAINERD_TOML_CONFIG written to /etc/containerd/conf.d/99-user.toml for containerd 2.x."
        logWarn "containerd 2.x uses different plugin tables (io.containerd.cri.v1.runtime, io.containerd.cri.v1.images)."
        logWarn "Custom settings targeting io.containerd.grpc.v1.cri will be silently ignored by containerd 2.x."
        logWarn "Migrate your CONTAINERD_TOML_CONFIG to the 2.x table layout to take effect."
    fi

    if [ "${config_schema_version:-2}" -ge "3" ]; then
        # Validate the effective merged config (base + all conf.d imports). A malformed or
        # un-loadable 99-user.toml makes `config dump` exit non-zero (verified on 2.0.5/2.1.0);
        # fail the install here, loudly, rather than after restart when containerd would refuse
        # to start. `config dump` is a config-load op and needs no running daemon.
        local dump_out=
        if ! dump_out="$(containerd --config /etc/containerd/config.toml config dump 2>&1)"; then
            bail "containerd rejected the merged config (check CONTAINERD_TOML_CONFIG / /etc/containerd/conf.d/99-user.toml):\n$dump_out"
        fi
        # The drop-in must survive the merge, proving the conf.d import is wired up. A user who
        # deliberately sets SystemdCgroup = false now wins the merge and trips this bail — that
        # is a correct, loud failure (kURL requires systemd cgroups), not a regression. Do not
        # weaken this guard to tolerate it.
        if ! echo "$dump_out" | grep -q 'SystemdCgroup = true'; then
            bail "containerd drop-in /etc/containerd/conf.d/50-replicated.toml was not applied to the merged config"
        fi
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

    log "Draining node to prepare for migration from docker to containerd"

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

    log "Cordoning node"

    local node=
    node="$(get_local_node_name)"
    kubectl "$kubeconfigFlag" cordon "$node"

    log "Deleting pods"
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

    log "Stopping kubelet"
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

    log "Migrated to containerd"
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

# return the pause image for the current version of kubernetes.versions 1.26
# and earlier return the empty string as they can be overridden to use a
# different image. for amazon 2023 we always patch the pause image.
function containerd_kubernetes_pause_image() {
    if [ is_amazon_2023 ] ; then
        cat "$DIR/packages/kubernetes/$KUBERNETES_VERSION/Manifest" | grep "pause" | awk '{ print $3 }'
        return
    fi

    local minor_version=
    minor_version="$(kubernetes_version_minor "$KUBERNETES_VERSION")"

    if [ "$minor_version" -ge "27" ]; then
        cat "$DIR/packages/kubernetes/$KUBERNETES_VERSION/Manifest" | grep "pause" | awk '{ print $3 }'
    else
        echo ""
    fi
}

# require_os_containerd ensures that the host package for containerd is installed if the OS is one we do not ship containerd packages for.
function require_os_containerd() {
    if use_os_containerd ; then
        ensure_host_package containerd containerd
        return
    fi
}

function require_centos8_containerd() {
    if [ "$LSB_DIST" == "centos" ] && [ "$DIST_VERSION_MAJOR" == "8" ]; then
        # if this is not centos 8 Stream, require preinstallation of containerd on 1.6.31+

        if cat /etc/centos-release | grep -q "CentOS Stream"; then
            # this is centos 8 stream, no need to check for containerd being installed
            return
        fi

        containerd_version_minor=
        containerd_version_minor=$(echo "$CONTAINERD_VERSION" | cut -d. -f2)
        containerd_version_patch=
        containerd_version_patch=$(echo "$CONTAINERD_VERSION" | cut -d. -f3)

        if [ "$containerd_version_minor" -eq "6" ] && [ "$containerd_version_patch" -ge "31" ]; then
            # if containerd is not installed, require preinstallation on 1.6.31+
            if yum_is_host_package_installed containerd.io ; then
                return
            fi

            bail "Containerd $CONTAINERD_VERSION is required to be preinstalled on CentOS 8.4 and earlier"
        fi
    fi
}
