
function prometheus() {
    local src="$DIR/addons/prometheus/0.46.0"
    local dst="$DIR/kustomize/prometheus"

    local operatorsrc="$src/operator"
    local operatordst="$dst/operator"

    local crdssrc="$src/crds"
    local crdsdst="$dst/crds"

    cp -r "$operatorsrc/" "$operatordst/"
    cp -r "$crdssrc/" "$crdsdst/"

    grafana_admin_secret "$src" "$operatordst"

    kubectl apply -k "$crdsdst/"
    spinner_until -1 prometheus_crd_ready

    prometheus_rook_ceph "$operatordst"

    # remove deployments and daemonsets that had labelselectors change (as those are immutable)
    kubectl delete deployment -n monitoring kube-state-metrics || true
    kubectl delete daemonset -n monitoring node-exporter || true
    kubectl delete deployment -n monitoring grafana || true
    kubectl delete deployment -n monitoring prometheus-adapter || true
    kubectl delete deployment -n monitoring prometheus-operator || true

    # remove things that had names change during upgrades
    kubectl delete alertmanager -n monitoring main || true

    # remove services that had a clusterip change
    kubectl delete service -n monitoring kube-state-metrics || true
    kubectl delete service -n monitoring prometheus-operator || true

    kubectl apply -k "$operatordst/"
}

GRAFANA_ADMIN_USER=
GRAFANA_ADMIN_PASS=
function grafana_admin_secret() {
    if kubernetes_resource_exists monitoring secret grafana-admin; then
        return 0
    fi

    local src="$1"
    local grafanadst="$2"

    GRAFANA_ADMIN_USER=admin
    GRAFANA_ADMIN_PASS=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c9)

    insert_resources "$grafanadst/kustomization.yaml" grafana-secret.yaml

    render_yaml_file "$src/tmpl-grafana-secret.yaml" > "$grafanadst/grafana-secret.yaml"
}

function prometheus_outro() {
    printf "\n"
    printf "\n"
    printf "The UIs of Prometheus, Grafana and Alertmanager have been exposed on NodePorts ${GREEN}30900${NC}, ${GREEN}30902${NC} and ${GREEN}30903${NC} respectively.\n"
    if [ -n "$GRAFANA_ADMIN_PASS" ]; then
        printf "\n"
        printf "To access Grafana use the generated user:password of ${GREEN}${GRAFANA_ADMIN_USER:-admin}:${GRAFANA_ADMIN_PASS} .${NC}\n"
    fi
    printf "\n"
    printf "\n"
}

function prometheus_crd_ready() {
    # https://github.com/coreos/kube-prometheus#quickstart
    if ! kubectl get customresourcedefinitions servicemonitors.monitoring.coreos.com &>/dev/null; then
        return 1
    fi
    if ! kubectl get servicemonitors --all-namespaces &>/dev/null; then
        return 1
    fi
    if ! kubectl get customresourcedefinitions prometheuses.monitoring.coreos.com &>/dev/null; then
        return 1
    fi
    if ! kubectl get prometheuses --all-namespaces &>/dev/null; then
        return 1
    fi
    return 0
}

function prometheus_rook_ceph() {
    local dst="$1"

    if kubectl get ns | grep -q rook-ceph; then
            insert_resources "$dst/kustomization.yaml" rook-ceph-rolebindings.yaml
    fi
}

function prometheus_preflight() {
    local src="${DIR}/addons/prometheus/${PROMETHEUS_VERSION}"
    echo "${src}/host-preflight.yaml"
}
