
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

# check_proxy_config tries to check if is possible connect with the registry
# If the result is an error that is  NOT UNAUTHORIZED such as:
# {"errors":[{"code":"UNAUTHORIZED","message":"authentication required","detail":null}]}
# Then, it means that the proxy configuration does not affected the connection and it is not invalid.
function check_proxy_config() {
    if [ -n "$CONTAINERD_VERSION" ]; then
        logStep "Checking registry config with Containerd"

        config_file="/etc/containerd/config.toml"

        # Check if the config file exists
        if [ ! -f "$config_file" ]; then
            logWarn "File $config_file not found. Unable to check connection"
            return
        fi

        # Get IP and ca_file path from the config.toml file
        ip=$(cat "$config_file" | grep -oP '(?<=plugins\."io.containerd.grpc.v1.cri"\.registry\.configs\.").*(?="\.tls\])')
        ca_file=$(cat "$config_file" | grep -oP '(?<=ca_file = ").*(?=")')

        # Echo containerd Proxy config:
        proxy_config_file="/etc/systemd/system/containerd.service.d/http-proxy.conf"
        if [ -f "$proxy_config_file" ]; then
           echo "Containerd HTTP proxy config:"
           grep -v -e '^\[Service\]' -e '^# Generated by kURL' "$proxy_config_file"
           echo ""
        fi

        # Execute curl command and capture the output
        set +e
        echo "curl --cacert $ca_file https://$ip/v2/"
        response=$(curl --cacert "$ca_file" "https://$ip/v2/" 2>&1)
        curl_exit_code=$?
        set -e

        # Check if the curl command failed or response doesn't contain "UNAUTHORIZED"
        if [ $curl_exit_code -ne 0 ] && [[ ! $response == *"UNAUTHORIZED"* ]]; then
            logWarn "Connection with registry failed! Check the installer configuration."
            printf "${YELLOW}\n"
            echo "Response: ${response}"
            printf "${NC}\n"
            logWarn "If you are using a Proxy, ensure that it is a valid Proxy and properly configured."
            logWarn "More info: https://kurl.sh/docs/install-with-kurl/proxy-installs"
        else
            logSuccess "Registry config with Containerd checked successfully"
        fi
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
