
function proxy_bootstrap() {
    if [ "$AIRGAP" = "1" ]; then
        return
    fi
    if curl --silent --connect-timeout 4 --fail https://api.replicated.com/market/v1/echo/ip > /dev/null ; then
        return
    fi
    # Need to peek at the yaml spec to find if a proxy is needed to download the util binaries
    if [ -n "$INSTALLER_SPEC_FILE" ]; then
        local overrideProxy=$(grep "proxyAddress:" "$INSTALLER_SPEC_FILE" | grep -o "http[^'\" ]*")
        if [ -n "$overrideProxy" ]; then
            export https_proxy="$overrideProxy"
            echo "Bootstrapped proxy address from installer spec file: $https_proxy"
            return
        fi
    fi
    local proxy=$(echo "$INSTALLER_YAML" | grep "proxyAddress:" | grep -o "http[^'\" ]*")
    if [ -n "$proxy" ]; then
        export https_proxy="$proxy"
        echo "Bootstrapped proxy address from installer yaml: $https_proxy"
        return
    fi

    bail "Failed to make outbound https request and no proxy is configured."
}

function configure_proxy() {
    if [ "$NO_PROXY" = "1" ]; then
        unset PROXY_ADDRESS
        return
    fi
    if [ -z "$PROXY_ADDRESS" ]; then
        return
    fi

    # for curl to download packages
    export https_proxy="$PROXY_ADDRESS"

    if ! curl --silent --fail --connect-timeout 4 https://api.replicated.com/market/v1/echo/ip >/dev/null ; then
        bail "Failed to make outbound request using proxy address $https_proxy"
    fi
}

function configure_no_proxy() {
    if [ -z "$PROXY_ADDRESS" ]; then
        return
    fi

    local addresses="localhost,127.0.0.1,.svc,.local,.default,kubernetes"

    if [ -n "$KOTSADM_VERSION" ]; then
        addresses="${addresses},kotsadm-api-node"
    fi
    if [ -n "$ROOK_VERSION" ]; then
        addresses="${addresses},.rook-ceph"
    fi
    if [ -n "$FLUENTD_VERSION" ]; then
        addresses="${addresses},.logging"
    fi
    if [ -n "$REGISTRY_VERSION" ]; then
        addresses="${addresses},.kurl"
    fi
    if [ -n "$PROMETHEUS_VERSION" ]; then
        addresses="${addresses},.monitoring"
    fi
    if [ -n "$VELERO_VERSION" ] && [ -n "$VELERO_NAMESPACE" ]; then
        addresses="${addresses},.${VELERO_NAMESPACE}"
    fi
    if [ -n "$MINIO_VERSION" ] && [ -n "$MINIO_NAMESPACE" ]; then
        addresses="${addresses},.${MINIO_NAMESPACE}"
    fi

    if [ -n "$PRIVATE_ADDRESS" ]; then
        addresses="${addresses},${PRIVATE_ADDRESS}"
    fi
    if [ -n "$LOAD_BALANCER_ADDRESS" ]; then
        addresses="${addresses},${LOAD_BALANCER_ADDRESS}"
    fi
    if [ -n "$KUBERNETES_MASTER_ADDR" ]; then
        addresses="${addresses},${KUBERNETES_MASTER_ADDR}"
    fi
    if [ -n "$POD_CIDR" ]; then
        addresses="${addresses},${POD_CIDR}"
    fi
    if [ -n "$SERVICE_CIDR" ]; then
        addresses="${addresses},${SERVICE_CIDR}"
    fi
    if [ -n "$ADDITIONAL_NO_PROXY_ADDRESSES" ]; then
        addresses="${addresses},${ADDITIONAL_NO_PROXY_ADDRESSES}"
    fi

    # filter duplicates
    addresses=$(echo "$addresses" | sed 's/,/\n/g' | sort | uniq | paste -s --delimiters=",")

    # kubeadm requires this in the environment to reach K8s masters
    export no_proxy="$addresses"
    NO_PROXY_ADDRESSES="$addresses"
    echo "Exported no_proxy: $no_proxy"
}
