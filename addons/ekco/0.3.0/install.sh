
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
    if [ "$EKCO_ENABLE_PURGE_DEAD_NODES" = "1" ]; then
        EKCO_PURGE_DEAD_NODES=true
    fi
    EKCO_CLEAR_DEAD_NODES=true
    if [ "$EKCO_DISABLE_CLEAR_DEAD_NODES" = "1" ]; then
        EKCO_CLEAR_DEAD_NODES=false
    fi
}

function ekco() {
    local src="$DIR/addons/ekco/0.3.0"
    local dst="$DIR/kustomize/ekco"

    cp "$src/kustomization.yaml" "$dst/kustomization.yaml"
    cp "$src/namespace.yaml" "$dst/namespace.yaml"
    cp "$src/rbac.yaml" "$dst/rbac.yaml"
    cp "$src/rolebinding.yaml" "$dst/rolebinding.yaml"
    cp "$src/deployment.yaml" "$dst/deployment.yaml"

    # is rook enabled
    if kubectl get ns | grep -q rook-ceph; then
        cp "$src/rbac-rook.yaml" "$dst/rbac-rook.yaml"
        insert_resources "$dst/kustomization.yaml" rbac-rook.yaml
        cat "$src/rolebinding-rook.yaml" >> "$dst/rolebinding.yaml"
    else
        EKCO_SHOULD_MAINTAIN_ROOK_STORAGE_NODES=false
        # disable reboot service for now as it only serves rook-ceph clusters
        EKCO_SHOULD_INSTALL_REBOOT_SERVICE=0
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

    ekco_install_purge_node_command "$src"
}

function ekco_join() {
    local src="$DIR/addons/ekco/0.3.0"

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

function ekco_install_purge_node_command() {
    local src="$1"

    cp "$src/ekco-purge-node.sh" /usr/local/bin/ekco-purge-node
    chmod u+x /usr/local/bin/ekco-purge-node
}
