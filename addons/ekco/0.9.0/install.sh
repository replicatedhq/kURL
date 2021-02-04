
function ekco_pre_init() {
    if [ -z "$EKCO_NODE_UNREACHABLE_TOLERATION_DURATION" ]; then
        EKCO_NODE_UNREACHABLE_TOLERATION_DURATION=5m
    fi
    if [ -z "$EKCO_MIN_READY_MASTER_NODE_COUNT" ]; then
        EKCO_MIN_READY_MASTER_NODE_COUNT=2
    fi
    if [ -z "$EKCO_MIN_READY_WORKER_NODE_COUNT" ]; then
        EKCO_MIN_READY_WORKER_NODE_COUNT=0
    fi
    EKCO_SHOULD_MAINTAIN_ROOK_STORAGE_NODES=true
    if [ "$EKCO_ROOK_SHOULD_USE_ALL_NODES" = "1" ]; then
        EKCO_SHOULD_MAINTAIN_ROOK_STORAGE_NODES=false
    fi
    EKCO_SHOULD_INSTALL_REBOOT_SERVICE=1
    if [ "$EKCO_SHOULD_DISABLE_REBOOT_SERVICE" = "1" ]; then
        EKCO_SHOULD_INSTALL_REBOOT_SERVICE=0
    fi
    EKCO_PURGE_DEAD_NODES=false
    if [ "$EKCO_SHOULD_ENABLE_PURGE_NODES" = "1" ]; then
        EKCO_PURGE_DEAD_NODES=true
    fi
    EKCO_CLEAR_DEAD_NODES=true
    if [ "$EKCO_SHOULD_DISABLE_CLEAR_NODES" = "1" ]; then
        EKCO_CLEAR_DEAD_NODES=false
    fi
    if [ "$ROOK_VERSION" = "1.0.4" ]; then
        EKCO_ROOK_PRIORITY_CLASS="node-critical"
    fi
}

function ekco() {
    local src="$DIR/addons/ekco/$EKCO_VERSION"
    local dst="$DIR/kustomize/ekco"

    cp "$src/kustomization.yaml" "$dst/kustomization.yaml"
    cp "$src/namespace.yaml" "$dst/namespace.yaml"
    cp "$src/rbac.yaml" "$dst/rbac.yaml"
    cp "$src/rolebinding.yaml" "$dst/rolebinding.yaml"
    cp "$src/deployment.yaml" "$dst/deployment.yaml"
    cp "$src/rotate-certs-rbac.yaml" "$dst/rotate-certs-rbac.yaml"

    # is rook enabled
    if kubectl get ns | grep -q rook-ceph; then
        cp "$src/rbac-rook.yaml" "$dst/rbac-rook.yaml"
        insert_resources "$dst/kustomization.yaml" rbac-rook.yaml
        cat "$src/rolebinding-rook.yaml" >> "$dst/rolebinding.yaml"

        if [ -n "$EKCO_ROOK_PRIORITY_CLASS" ]; then
            kubectl label namespace rook-ceph rook-priority.kurl.sh="" --overwrite
        fi
    else
        EKCO_SHOULD_MAINTAIN_ROOK_STORAGE_NODES=false
    fi

    render_yaml_file "$src/tmpl-configmap.yaml" > "$dst/configmap.yaml"
    insert_resources "$dst/kustomization.yaml" configmap.yaml

    kubectl apply -k "$dst"
    # apply rolebindings separately so as not to override the namespace
    kubectl apply -f "$dst/rolebinding.yaml"

    # delete pod to re-read the config map
    kubectl -n kurl delete pod -l app=ekc-operator 2>/dev/null || true

    if [ "$EKCO_SHOULD_INSTALL_REBOOT_SERVICE" = "1" ]; then
        ekco_install_reboot_service "$src"
    fi
    if [ -n "$EKCO_AUTO_UPGRADE_SCHEDULE" ] && [ "$AUTO_UPGRADES_ENABLED" = "1" ]; then
        ekco_install_upgrade_service "$src"
    else
        ekco_remove_upgrade_service
    fi

    ekco_install_purge_node_command "$src"
}

function ekco_join() {
    local src="$DIR/addons/ekco/$EKCO_VERSION"

    EKCO_SHOULD_INSTALL_REBOOT_SERVICE=1
    if [ "$EKCO_SHOULD_DISABLE_REBOOT_SERVICE" = "1" ]; then
        EKCO_SHOULD_INSTALL_REBOOT_SERVICE=0
    fi

    # is rook disabled
    if [ -z "$ROOK_VERSION" ]; then
        # disable reboot service for now as it only serves rook-ceph clusters
        EKCO_SHOULD_INSTALL_REBOOT_SERVICE=0
    fi

    if [ "$EKCO_SHOULD_INSTALL_REBOOT_SERVICE" = "1" ]; then
        ekco_install_reboot_service "$src"
    fi

    if kubernetes_is_master; then
        ekco_install_purge_node_command "$src"
    fi
}

function ekco_install_reboot_service() {
    local src="$1"

    mkdir -p /opt/ekco
    cp "$src/reboot/startup.sh" /opt/ekco/startup.sh
    cp "$src/reboot/shutdown.sh" /opt/ekco/shutdown.sh
    cp "$src/reboot/ekco-reboot.service" /etc/systemd/system/ekco-reboot.service
    chmod u+x /opt/ekco/startup.sh
    chmod u+x /opt/ekco/shutdown.sh

    systemctl daemon-reload
    systemctl enable ekco-reboot.service
    systemctl start ekco-reboot.service
}

function ekco_install_upgrade_service() {
    local src="$1"

    if [ "$AIRGAP" = "1" ]; then
        echo "Auto-upgrade service will not be installed in airgap mode"
        return 0
    fi
    if [ -z "$KURL_URL" ] || [ -z "$INSTALLER_ID" ]; then
        echo "Auto-upgrade service will not be installed without KURL_URL and INSTALLER_ID"
        return 0
    fi

    mkdir -p /opt/ekco
    render_file "$src/upgrade/ekco-upgrade.service" > /etc/systemd/system/ekco-upgrade.service
    render_file "$src/upgrade/ekco-upgrade.timer" > /etc/systemd/system/ekco-upgrade.timer
    cp "$src/upgrade/upgrade.sh" /opt/ekco/upgrade.sh
    chmod u+x /opt/ekco/upgrade.sh

    local latest=$(curl -I $KURL_URL/$INSTALLER_ID | grep -i 'X-Kurl-Hash' | awk '{ print $2 }' | tr -d '\r')
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") $latest" >> /opt/ekco/upgrades.txt

    systemctl daemon-reload
    systemctl enable ekco-upgrade.timer
    systemctl start ekco-upgrade.timer
}

function ekco_remove_upgrade_service() {
    if systemctl is-active -q ekco-upgrade.timer 2>/dev/null; then
        systemctl stop ekco-upgrade.timer
    fi
    if systemctl is-enabled -q ekco-upgrade.timer 2>/dev/null; then
        systemctl disable ekco-upgrade.timer
    fi
    rm_file /etc/systemd/system/ekco-upgrade.service
    rm_file /etc/systemd/system/ekco-upgrade.timer
    rm_file /opt/ekco/upgrade.sh
    rm_file /opt/ekco/upgrades.txt
}

function ekco_install_purge_node_command() {
    local src="$1"

    cp "$src/ekco-purge-node.sh" /usr/local/bin/ekco-purge-node
    chmod u+x /usr/local/bin/ekco-purge-node
}

function ekco_handle_load_balancer_address_change_pre_init() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        return 0
    fi

    splitHostPort $1
    local oldLoadBalancerHost=$HOST
    splitHostPort $2
    local newLoadBalancerHost=$HOST

    if [ "$oldLoadBalancerHost" = "$newLoadBalancerHost" ]; then
        return 0
    fi

    local ARG=--add-alt-names=$newLoadBalancerHost

    for NODE in ${KUBERNETES_REMOTE_PRIMARIES[@]}; do
        echo "Adding new load balancer $newLoadBalancerHost to API server certificate on node $NODE"
        local podName=regen-cert-$NODE
        kubectl delete pod $podName --force --grace-period=0 2>/dev/null || true
        render_yaml_file "$DIR/addons/ekco/$EKCO_VERSION/regen-cert-pod.yaml" | kubectl apply -f -
        spinner_until 120 kubernetes_pod_started $podName default
        kubectl logs -f $podName
        spinner_until 10 kubernetes_pod_completed $podName default
        local phase=$(kubectl get pod $podName -ojsonpath='{ .status.phase }')
        if [ "$phase" != "Succeeded" ]; then
            bail "Pod $podName phase: $phase"
        fi
        kubectl delete pod $podName --force --grace-period=0
    done

    # Wait for the servers to pick up the new certs
    for NODE in ${KUBERNETES_REMOTE_PRIMARIES[@]}; do
        local nodeIP=$(kubectl get node $NODE -owide  --no-headers | awk '{ print $6 }')
        echo "Waiting for $NODE to begin serving certificate signed for $newLoadBalancerHost"
        if ! spinner_until 120 cert_has_san "$nodeIP:6443" "$newLoadBalancerHost"; then
            printf "${YELLOW}$NODE is not serving certificate signed for $newLoadBalancerHost${NC}\n"
        fi
    done
}

function ekco_handle_load_balancer_address_change_post_init() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        return 0
    fi

    splitHostPort $1
    local oldLoadBalancerHost=$HOST
    splitHostPort $2
    local newLoadBalancerHost=$HOST

    if [ "$oldLoadBalancerHost" = "$newLoadBalancerHost" ]; then
        return 0
    fi

    local ARG=--drop-alt-names=$oldLoadBalancerHost

    for NODE in ${KUBERNETES_REMOTE_PRIMARIES[@]}; do
        echo "Removing old load balancer address $oldLoadBalancerHost from API server certificate on node $NODE"
        local podName=regen-cert-$NODE
        kubectl delete pod $podName --force --grace-period=0 2>/dev/null || true
        render_yaml_file "$DIR/addons/ekco/$EKCO_VERSION/regen-cert-pod.yaml" | kubectl apply -f -
        spinner_until 120 kubernetes_pod_started $podName default
        kubectl logs -f $podName
        spinner_until 10 kubernetes_pod_completed $podName default
        local phase=$(kubectl get pod $podName -ojsonpath='{ .status.phase }')
        if [ "$phase" != "Succeeded" ]; then
            bail "Pod $podName phase: $phase"
        fi
        kubectl delete pod $podName --force --grace-period=0
    done
}
