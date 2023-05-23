# read_proxy_config_from_env makes sure that both proxy variables (upper
# and lower case) are set to the same value. for example http_proxy and
# HTTP_PROXY both must point to the same address. this function sets the
# following variables ENV_HTTP_PROXY_ADDRESS, ENV_HTTPS_PROXY_ADDRESS,
# and ENV_NO_PROXY.
function read_proxy_config_from_env() {
    # by default https proxy configuration inherits from http proxy config.
    # we also make sure that we have both environment variables (with upper
    # and lower case) set to the same value.
    if [ -n "$HTTP_PROXY" ]; then
        ENV_HTTP_PROXY_ADDRESS="$HTTP_PROXY"
        ENV_HTTPS_PROXY_ADDRESS="$HTTP_PROXY"
        export http_proxy="$HTTP_PROXY"
    elif [ -n "$http_proxy" ]; then
        ENV_HTTP_PROXY_ADDRESS="$http_proxy"
        ENV_HTTPS_PROXY_ADDRESS="$http_proxy"
        export HTTP_PROXY="$http_proxy"
    fi

    # if https proxy is explicitly set, it overrides the inherit http proxy
    # configuration. we also make sure we have both environment variables
    # (with upper and lower case) set to the same value.
    if [ -n "$HTTPS_PROXY" ]; then
        ENV_HTTPS_PROXY_ADDRESS="$HTTPS_PROXY"
        export https_proxy="$HTTPS_PROXY"
    elif [ -n "$https_proxy" ]; then
        ENV_HTTPS_PROXY_ADDRESS="$https_proxy"
        export HTTPS_PROXY="$https_proxy"
    fi

    # no proxy is simply copied from the environment. we also make sure
    # we have both environment variables (with upper and lower case) set
    # to the same value.
    if [ -n "$NO_PROXY" ]; then
        ENV_NO_PROXY="$NO_PROXY"
        export no_proxy="$NO_PROXY"
    elif [ -n "$no_proxy" ]; then
        ENV_NO_PROXY="$no_proxy"
        export NO_PROXY="$no_proxy"
    fi

    # if proxy is configured we need to make sure that kubectl can reach
    # the apiserver without going through the proxy.
    if [ -n "$ENV_HTTP_PROXY_ADDRESS" ] || [ -n "$ENV_HTTPS_PROXY_ADDRESS" ]; then
        kubectl_no_proxy
    fi
}

# proxy_bootstrap reads the proxy configuration from the environment and
# overrides them with the configuration provided by the user through the
# installer yaml. at the end of this process three variables are set:
# ENV_HTTP_PROXY_ADDRESS, ENV_HTTPS_PROXY_ADDRESS, and ENV_NO_PROXY.
function proxy_bootstrap() {
    # read and sanitize proxy configuration from environment variables.
    read_proxy_config_from_env

    # users can still provide a different proxy by patching the installer
    # yaml, we need to verify if this is the case and then use the proxy
    # set in the yaml for both http and https.
    if [ -n "$INSTALLER_SPEC_FILE" ]; then
        local overrideProxy=$(grep "proxyAddress:" "$INSTALLER_SPEC_FILE" | grep -o "http[^'\" ]*")
        if [ -n "$overrideProxy" ]; then
            ENV_HTTP_PROXY_ADDRESS="$overrideProxy"
            ENV_HTTPS_PROXY_ADDRESS="$overrideProxy"
            export http_proxy="$overrideProxy"
            export https_proxy="$overrideProxy"
            export HTTP_PROXY="$overrideProxy"
            export HTTPS_PROXY="$overrideProxy"
            echo "Bootstrapped proxy address from installer spec file: $https_proxy"
            return
        fi
    fi

    local proxy=$(echo "$INSTALLER_YAML" | grep "proxyAddress:" | grep -o "http[^'\" ]*")
    if [ -z "$proxy" ]; then
        return
    fi
    ENV_HTTP_PROXY_ADDRESS="$proxy"
    ENV_HTTPS_PROXY_ADDRESS="$proxy"
    export http_proxy="$proxy"
    export https_proxy="$proxy"
    export HTTP_PROXY="$proxy"
    export HTTPS_PROXY="$proxy"
    echo "Bootstrapped proxy address from installer yaml: $https_proxy"
}

# kubectl_no_proxy makes sure that kubectl can reach the apiserver without
# going through the proxy. this is done by adding the apiserver address to
# the NO_PROXY and no_proxy environment variable. this function expects 
# both upper and lower case variables to be already sanitized (to contain
# the same value).
function kubectl_no_proxy() {
    if [ ! -f /etc/kubernetes/admin.conf ]; then
        return
    fi
    kubectlEndpoint=$(cat /etc/kubernetes/admin.conf  | grep 'server:' | awk '{ print $NF }' | sed -E 's/https?:\/\///g')
    splitHostPort "$kubectlEndpoint"
    if [ -n "$no_proxy" ]; then
        export no_proxy="$no_proxy,$HOST"
        export NO_PROXY="$NO_PROXY,$HOST"
    else
        export no_proxy="$HOST"
        export NO_PROXY="$HOST"
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

    if [ -z "$PROXY_ADDRESS" ] && [ -z "$ENV_HTTP_PROXY_ADDRESS" ] && [ -z "$ENV_HTTPS_PROXY_ADDRESS" ]; then
        log "Not using proxy address"
        return
    fi

    # if the proxy has been set in the installer we use that one for both
    # http and https.
    if [ -n "$PROXY_ADDRESS" ]; then
        logWarn "Overriding HTTP and HTTPS proxies addresses with $PROXY_ADDRESS"
        PROXY_HTTPS_ADDRESS="$PROXY_ADDRESS"
        return
    fi

    # if user hasn't provide any proxy configuration we use the ones
    # present in the environment.
    PROXY_ADDRESS="$ENV_HTTP_PROXY_ADDRESS"
    PROXY_HTTPS_ADDRESS="$ENV_HTTP_PROXY_ADDRESS"
    if [ -n "$ENV_HTTPS_PROXY_ADDRESS" ]; then
        PROXY_HTTPS_ADDRESS="$ENV_HTTPS_PROXY_ADDRESS"
    fi
    echo "Using system proxies, HTTP: $PROXY_ADDRESS, HTTPS: $PROXY_HTTPS_ADDRESS"
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
