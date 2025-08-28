
function goldpinger() {
    local src="$DIR/addons/goldpinger/__GOLDPINGER_VERSION__"
    local dst="$DIR/kustomize/goldpinger"
    
    # Check if upgrading from old okgolove chart
    if is_old_chart; then
        logStep "Migrating goldpinger from okgolove to Bloomberg chart..."
        
        # Clean uninstall of old okgolove chart resources
        kubectl delete daemonset -n kurl goldpinger --ignore-not-found=true
        kubectl delete configmap -n kurl goldpinger-zap --ignore-not-found=true
        kubectl delete service -n kurl goldpinger --ignore-not-found=true
        kubectl delete serviceaccount -n kurl goldpinger --ignore-not-found=true
        kubectl delete clusterrole goldpinger-clusterrole --ignore-not-found=true
        kubectl delete clusterrolebinding goldpinger-clusterrolebinding --ignore-not-found=true
        
        # Wait for old pods to terminate
        kubectl wait --for=delete pod -l app.kubernetes.io/name=goldpinger -n kurl --timeout=30s || true
        
        logStep "Installing Bloomberg goldpinger chart..."
    else
        logStep "Installing goldpinger __GOLDPINGER_VERSION__..."
    fi

    cp "$src/kustomization.yaml" "$dst/"
    cp "$src/goldpinger.yaml" "$dst/"
    cp "$src/servicemonitor.yaml" "$dst/"
    cp "$src/troubleshoot.yaml" "$dst/"

    if [ -n "${PROMETHEUS_VERSION}" ]; then
        insert_resources "$dst/kustomization.yaml" servicemonitor.yaml
    fi

    kubectl apply -k "$dst/"

    logStep "Waiting for the Goldpinger Daemonset to be ready"
    spinner_until 180 goldpinger_daemonset
    logStep "Waiting for the Goldpinger service to be ready"
    spinner_until 120 kubernetes_service_healthy kurl goldpinger
    logSuccess "Goldpinger __GOLDPINGER_VERSION__ is ready"
}

function is_old_chart() {
    # Check for okgolove chart versions (4.x, 5.x, 6.x)
    kubectl get daemonset -n kurl goldpinger \
        -o jsonpath="{.metadata.labels['helm\.sh/chart']}" 2>/dev/null | \
        grep -E "goldpinger-(4|5|6)\." &>/dev/null
}

function goldpinger_daemonset() {
    local desired=$(kubectl get daemonsets -n kurl goldpinger --no-headers | tr -s ' ' | cut -d ' ' -f2)
    local ready=$(kubectl get daemonsets -n kurl goldpinger --no-headers | tr -s ' ' | cut -d ' ' -f4)
    local uptodate=$(kubectl get daemonsets -n kurl goldpinger --no-headers | tr -s ' ' | cut -d ' ' -f5)

    if [ "$desired" = "$ready" ] ; then
        if [ "$desired" = "$uptodate" ] ; then
            return 0
        fi
    fi
    return 1
}
