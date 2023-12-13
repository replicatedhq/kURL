
function goldpinger() {
    local src="$DIR/addons/goldpinger/__GOLDPINGER_VERSION__"
    local dst="$DIR/kustomize/goldpinger"

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
    logSuccess "Goldpinger is ready and monitoring node network health"
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
