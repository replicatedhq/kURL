
function proxy_bootstrap() {
    if [ -n "$HTTP_PROXY" ]; then
        ENV_PROXY_ADDRESS="$HTTP_PROXY"
        export https_proxy="$HTTP_PROXY"
        printf "The installer will use the proxy at '%s' (imported from env var 'HTTP_PROXY')\n" "$ENV_PROXY_ADDRESS"
    elif [ -n "$http_proxy" ]; then
        ENV_PROXY_ADDRESS="$http_proxy"
        export https_proxy="$http_proxy"
        printf "The installer will use the proxy at '%s' (imported from env var 'http_proxy')\n" "$ENV_PROXY_ADDRESS"
    elif [ -n "$HTTPS_PROXY" ]; then
        ENV_PROXY_ADDRESS="$HTTPS_PROXY"
        printf "The installer will use the proxy at '%s' (imported from env var 'HTTPS_PROXY')\n" "$ENV_PROXY_ADDRESS"
    elif [ -n "$https_proxy" ]; then
        ENV_PROXY_ADDRESS="$https_proxy"
        printf "The installer will use the proxy at '%s' (imported from env var 'https_proxy')\n" "$ENV_PROXY_ADDRESS"
    fi

    if [ -n "$NO_PROXY" ]; then
        ENV_NO_PROXY="$NO_PROXY"
    elif [ -n "$no_proxy" ]; then
        ENV_NO_PROXY="$no_proxy"
    fi

    # Need to peek at the yaml spec to find if a proxy is needed to download the util binaries
    if [ -n "$INSTALLER_SPEC_FILE" ]; then
        local overrideProxy=$(grep "proxyAddress:" "$INSTALLER_SPEC_FILE" | grep -o "http[^'\" ]*")
        if [ -n "$overrideProxy" ]; then
            export https_proxy="$overrideProxy"
            kubectl_no_proxy
            echo "Bootstrapped proxy address from installer spec file: $https_proxy"
            return
        fi
    fi
    local proxy=$(echo "$INSTALLER_YAML" | grep "proxyAddress:" | grep -o "http[^'\" ]*")
    if [ -n "$proxy" ]; then
        export https_proxy="$proxy"
        kubectl_no_proxy
        echo "Bootstrapped proxy address from installer yaml: $https_proxy"
        return
    fi

    if [ -n "$ENV_PROXY_ADDRESS" ]; then
        export https_proxy="$ENV_PROXY_ADDRESS"
        kubectl_no_proxy
        log "Bootstrapped proxy address from ENV_PROXY_ADDRESS: $https_proxy"
        return
    fi
}

function kubectl_no_proxy() {
    if [ ! -f /etc/kubernetes/admin.conf ]; then
        return
    fi
    kubectlEndpoint=$(cat /etc/kubernetes/admin.conf  | grep 'server:' | awk '{ print $NF }' | sed -E 's/https?:\/\///g')
    splitHostPort "$kubectlEndpoint"
    if [ -n "$no_proxy" ]; then
        export no_proxy="$no_proxy,$HOST"
    else
        export no_proxy="$HOST"
    fi
}

function configure_proxy() {
    if [ "$NO_PROXY" = "1" ]; then
        echo "Not using http proxy"
        unset PROXY_ADDRESS
        unset http_proxy
        unset HTTP_PROXY
        unset https_proxy
        unset HTTPS_PROXY
        return
    fi
    if [ -z "$PROXY_ADDRESS" ] && [ -z "$ENV_PROXY_ADDRESS" ]; then
        log "Not using proxy address"
        return
    fi
    if [ -z "$PROXY_ADDRESS" ]; then
        PROXY_ADDRESS="$ENV_PROXY_ADDRESS"
    fi
    export https_proxy="$PROXY_ADDRESS"
    echo "Using proxy address $PROXY_ADDRESS"
}

function configure_no_proxy_preinstall() {
    if [ -z "$PROXY_ADDRESS" ]; then
        return
    fi

    local addresses="localhost,127.0.0.1,.svc,.local,.default,kubernetes"

    if [ -n "$ENV_NO_PROXY" ]; then
        addresses="${addresses},${ENV_NO_PROXY}"
    fi
    if [ -n "$PRIVATE_ADDRESS" ]; then
        addresses="${addresses},${PRIVATE_ADDRESS}"
    fi
    if [ -n "$LOAD_BALANCER_ADDRESS" ]; then
        addresses="${addresses},${LOAD_BALANCER_ADDRESS}"
    fi
    if [ -n "$ADDITIONAL_NO_PROXY_ADDRESSES" ]; then
        addresses="${addresses},${ADDITIONAL_NO_PROXY_ADDRESSES}"
    fi

    # filter duplicates
    addresses=$(unique_no_proxy_addresses "$addresses")

    # kubeadm requires this in the environment to reach K8s masters
    export no_proxy="$addresses"
    NO_PROXY_ADDRESSES="$addresses"
    echo "Exported no_proxy: $no_proxy"
}

function configure_no_proxy() {
    if [ -z "$PROXY_ADDRESS" ]; then
        return
    fi

    local addresses="localhost,127.0.0.1,.svc,.local,.default,kubernetes"

    if [ -n "$ENV_NO_PROXY" ]; then
        addresses="${addresses},${ENV_NO_PROXY}"
    fi
    if [ -n "$KOTSADM_VERSION" ]; then
        addresses="${addresses},kotsadm-rqlite,kotsadm-api-node"
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
    addresses=$(unique_no_proxy_addresses "$addresses")

    # kubeadm requires this in the environment to reach K8s masters
    export no_proxy="$addresses"
    NO_PROXY_ADDRESSES="$addresses"
    echo "Exported no_proxy: $no_proxy"
}

function unique_no_proxy_addresses() {
    echo "$1" | sed 's/,/\n/g' | sed '/^\s*$/d' | sort | uniq | paste -s --delimiters=","
}
