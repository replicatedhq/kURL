
function ekco_pre_init() {
    if [ -z "$EKCO_NODE_UNREACHABLE_TOLERATION_DURATION" ]; then
        EKCO_NODE_UNREACHABLE_TOLERATION_DURATION=1h
    fi
    if [ -z "$EKCO_MIN_READY_MASTER_NODE_COUNT" ]; then
        EKCO_MIN_READY_MASTER_NODE_COUNT=2
    fi
    if [ -z "$EKCO_MIN_READY_WORKER_NODE_COUNT" ]; then
        EKCO_MIN_READY_WORKER_NODE_COUNT=0
    fi
    EKCO_SHOULD_MAINTAIN_ROOK_STORAGE_NODES=true
    if [ "$EKCO_DISABLE_SHOULD_MAINTAIN_ROOK_STORAGE_NODES" = "1" ]; then
        EKCO_SHOULD_MAINTAIN_ROOK_STORAGE_NODES=false
    fi
}

function ekco() {
    local src="$DIR/addons/ekco/0.1.0"
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
    fi

    render_yaml_file "$src/tmpl-configmap.yaml" > "$dst/configmap.yaml"
    insert_resources "$dst/kustomization.yaml" configmap.yaml

    kubectl apply -k "$dst"
    # apply rolebindings separately so as not to override the namespace
    kubectl apply -f "$dst/rolebinding.yaml"

    # delete pod to re-read the config map
    kubectl -n kurl delete pod -l app=ekc-operator 2>/dev/null || true
}
