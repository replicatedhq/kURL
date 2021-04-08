
function prometheus() {
    local src="$DIR/addons/prometheus/0.33.0"
    local dst="$DIR/kustomize/prometheus"

    local operatorsrc="$src/operator"
    local operatordst="$dst/operator"

    local monitorssrc="$src/monitors"
    local monitorsdst="$dst/monitors"

    local grafanasrc="$src/grafana"
    local grafanadst="$dst/grafana"

    cp -r "$operatorsrc/" "$operatordst/"
    cp -r "$monitorssrc/" "$monitorsdst/"
    cp -r "$grafanasrc/" "$grafanadst/"

    grafana_admin_secret "$src" "$grafanadst"

    kubectl apply -k "$operatordst/"

    spinner_until -1 prometheus_crd_ready

    prometheus_rook_ceph "$dst"

    kubectl apply -k "$monitorsdst/"
    kubectl apply -k "$grafanadst/"
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

    insert_resources "$grafanadst/kustomization.yaml" secret.yaml

    render_yaml_file "$src/tmpl-grafana-secret.yaml" > "$grafanadst/secret.yaml"
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
        cat <<EOF >> "$dst/monitors/prometheus-roleBindingSpecificNamespaces.yaml"
- apiVersion: rbac.authorization.k8s.io/v1
  kind: RoleBinding
  metadata:
    name: prometheus-k8s
    namespace: rook-ceph
  roleRef:
    apiGroup: rbac.authorization.k8s.io
    kind: Role
    name: prometheus-k8s
  subjects:
  - kind: ServiceAccount
    name: prometheus-k8s
    namespace: monitoring
EOF

        cat <<EOF >> "$dst/monitors/prometheus-roleSpecificNamespaces.yaml"
- apiVersion: rbac.authorization.k8s.io/v1
  kind: Role
  metadata:
    name: prometheus-k8s
    namespace: rook-ceph
  rules:
  - apiGroups:
    - ""
    resources:
    - services
    - endpoints
    - pods
    verbs:
    - get
    - list
    - watch
EOF
    fi
}

function prometheus_preflight() {
    local src="${DIR}/addons/prometheus/${PROMETHEUS_VERSION}"
    echo "${src}/host-preflight.yaml"
}
