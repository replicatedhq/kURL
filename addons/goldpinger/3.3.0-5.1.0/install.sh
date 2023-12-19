
function goldpinger() {
    local src="$DIR/addons/goldpinger/3.3.0-5.1.0"
    local dst="$DIR/kustomize/goldpinger"

    cp "$src/kustomization.yaml" "$dst/"
    cp "$src/goldpinger.yaml" "$dst/"
    cp "$src/servicemonitor.yaml" "$dst/"

    if [ -n "${PROMETHEUS_VERSION}" ]; then
        insert_resources "$dst/kustomization.yaml" servicemonitor.yaml
    fi

    kubectl apply -k "$dst/"

    echo "Waiting for Goldpinger  Daemonset to be ready"
    spinner_until 180 goldpinger_daemonset

}

function goldpinger_daemonset() {
    local desired=$(kubectl get daemonsets -n kurl goldpinger --no-headers | tr -s ' ' | cut -d ' ' -f2)
    local ready=$(kubectl get daemonsets -n kurl goldpinger --no-headers | tr -s ' ' | cut -d ' ' -f4)

    if [ "$desired" = "$ready" ] ; then
        return 0
    fi
    return 1
}
