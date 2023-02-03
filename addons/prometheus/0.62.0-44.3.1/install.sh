# shellcheck disable=SC2148

function prometheus() {
    local src="$DIR/addons/prometheus/0.62.0-44.3.1"
    local dst="$DIR/kustomize/prometheus"

    local operatorsrc="$src/operator"
    local operatordst="$dst/operator"

    local crdssrc="$src/crds"
    local crdsdst="$dst/crds"

    cp -r "$operatorsrc/" "$operatordst/"
    cp -r "$crdssrc/" "$crdsdst/"

    grafana_admin_secret "$src" "$operatordst"

    # Server-side apply is needed here because the CRDs are too large to keep in metadata
    # https://github.com/prometheus-community/helm-charts/issues/1500
    # Also delete any existing last-applied-configuration annotations for pre-122 clusters
    kubectl get crd | grep coreos.com | awk '{ print $1 }' | xargs -I {} kubectl patch crd {} --type=json -p='[{"op": "remove", "path": "/metadata/annotations/kubectl.kubernetes.io~1last-applied-configuration"}]' 2>/dev/null || true
    kubectl apply --server-side --force-conflicts -k "$crdsdst/"
    spinner_until -1 prometheus_crd_ready

    prometheus_rook_ceph "$operatordst"
    prometheus_longhorn "$operatordst"

    # remove deployments and daemonsets that had labelselectors change (as those are immutable)
    kubectl delete deployment -n monitoring kube-state-metrics || true
    kubectl delete daemonset -n monitoring node-exporter || true
    kubectl delete deployment -n monitoring grafana || true
    kubectl delete deployment -n monitoring prometheus-adapter || true

    # remove things that had names change during upgrades
    kubectl delete alertmanager -n monitoring main || true

    # remove services that had a clusterip change
    kubectl delete service -n monitoring kube-state-metrics || true
    kubectl delete service -n monitoring prometheus-operator || true

    # remove nodeport services that had names change
    kubectl delete service -n monitoring grafana || true
    kubectl delete service -n monitoring alertmanager-main || true
    kubectl delete service -n monitoring prometheus-k8s || true

    # if the prometheus-node-exporter daemonset exists and has a release labelSelector set, delete it
    if kubernetes_resource_exists monitoring daemonset prometheus-node-exporter; then
        local promNodeExporterLabelSelector=$(kubectl get daemonset -n monitoring prometheus-node-exporter --output="jsonpath={.spec.selector.matchLabels.release}")
        if [ -n "$promNodeExporterLabelSelector" ]; then
            kubectl delete daemonset -n monitoring prometheus-node-exporter || true
        fi
    fi

    # if the prometheus-operator deployment exists and has the wrong labelSelectors set, delete it
    if kubernetes_resource_exists monitoring deployment prometheus-operator; then
        local promOperatorLabelSelector=$(kubectl get deployment -n monitoring prometheus-operator --output="jsonpath={.spec.selector.matchLabels.release}") || true
        if [ -n "$promOperatorLabelSelector" ]; then
            kubectl delete deployment -n monitoring prometheus-operator || true
        fi

        promOperatorLabelSelector=$(kubectl get deployment -n monitoring prometheus-operator --output="jsonpath={.spec.selector.matchLabels.app\.kubernetes\.io/component}") || true
        if [ -n "$promOperatorLabelSelector" ]; then
            kubectl delete deployment -n monitoring prometheus-operator || true
        fi
    fi

    # the metrics service has been renamed to v1beta1.custom.metrics.k8s.io, delete the old
    if kubectl get --no-headers apiservice v1beta1.metrics.k8s.io 2>/dev/null | grep -q 'monitoring/prometheus-adapter' ; then
        kubectl delete apiservice v1beta1.metrics.k8s.io
    fi

    # change ClusterIP services to NodePorts if required
    if [ -z "$PROMETHEUS_SERVICE_TYPE" ] || [ "$PROMETHEUS_SERVICE_TYPE" = "NodePort" ] ; then
        cp "$src/nodeport-services.yaml" "$operatordst"
        insert_patches_strategic_merge "$operatordst/kustomization.yaml" nodeport-services.yaml
    fi

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
    if [ -z "$PROMETHEUS_SERVICE_TYPE" ] || [ "$PROMETHEUS_SERVICE_TYPE" = "NodePort" ] ; then
        printf "The UIs of Prometheus, Grafana and Alertmanager have been exposed on NodePorts ${GREEN}30900${NC}, ${GREEN}30902${NC} and ${GREEN}30903${NC} respectively.\n"
    else
        printf "The UIs of Prometheus, Grafana and Alertmanager have been exposed on internal ClusterIP services.\n"
    fi
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

function prometheus_longhorn() {
    local dst="$1"

    if kubectl get ns | grep -q longhorn-system; then
            insert_resources "$dst/kustomization.yaml" longhorn.yaml
    fi
}
