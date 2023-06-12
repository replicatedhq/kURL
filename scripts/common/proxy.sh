# read_proxy_config_from_env makes sure that both proxy variables (upper
# and lower case) are set to the same value. for example http_proxy and
# HTTP_PROXY both must point to the same address. this function sets the
# following variables ENV_HTTP_PROXY_ADDRESS, ENV_HTTPS_PROXY_ADDRESS,
# and ENV_NO_PROXY.
function read_proxy_config_from_env() {
    # by default https proxy configuration inherits from http proxy config.
    if [ -n "$HTTP_PROXY" ]; then
        ENV_HTTP_PROXY_ADDRESS="$HTTP_PROXY"
        ENV_HTTPS_PROXY_ADDRESS="$HTTP_PROXY"
    elif [ -n "$http_proxy" ]; then
        ENV_HTTP_PROXY_ADDRESS="$http_proxy"
        ENV_HTTPS_PROXY_ADDRESS="$http_proxy"
    fi

    # if https proxy is explicitly set, it overrides the inherit http proxy
    # configuration.
    if [ -n "$HTTPS_PROXY" ]; then
        ENV_HTTPS_PROXY_ADDRESS="$HTTPS_PROXY"
    elif [ -n "$https_proxy" ]; then
        ENV_HTTPS_PROXY_ADDRESS="$https_proxy"
    fi

    # no proxy is simply copied from the environment.
    if [ -n "$NO_PROXY" ]; then
        ENV_NO_PROXY="$NO_PROXY"
    elif [ -n "$no_proxy" ]; then
        ENV_NO_PROXY="$no_proxy"
    fi

    # here we sanitize the proxy configuration. we make sure that both upper
    # and lower case variables point to the same value.
    if [ -n "$ENV_HTTP_PROXY_ADDRESS" ]; then
        export http_proxy="$ENV_HTTP_PROXY_ADDRESS"
        export HTTP_PROXY="$ENV_HTTP_PROXY_ADDRESS"
    fi
    if [ -n "$ENV_HTTPS_PROXY_ADDRESS" ]; then
        export https_proxy="$ENV_HTTPS_PROXY_ADDRESS"
        export HTTPS_PROXY="$ENV_HTTPS_PROXY_ADDRESS"
    fi
    if [ -n "$ENV_NO_PROXY" ]; then
        export no_proxy="$ENV_NO_PROXY"
        export NO_PROXY="$ENV_NO_PROXY"
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
            kubectl_no_proxy
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
    kubectl_no_proxy
    echo "Bootstrapped proxy address from installer yaml: $https_proxy"
}

# check_proxy_config tries to check if is possible connect with the registry
# Th following code will check if the proxy is invalid by running crictl pull test/invalid/image:latest
# See that the image does not matter to us. We are looking here for proxy issues only and then, when the Proxy config
# not to be configured accurately we will face an issue like:
# E0525 09:01:01.952576 1399831 remote_image.go:167] "PullImage from image service failed" err="rpc error: code = Unknown desc = failed to pull and unpack image \"docker.io/test/invalid/image:latest\": failed to resolve reference \"docker.io/test/invalid/image:latest\": failed to do request: Head \"https://registry-1.docker.io/v2/test/invalid/image/manifests/latest\": proxyconnect tcp: dial tcp: lookup invalidproxy: Temporary failure in name resolution" image="test/invalid/image:latest"
# FATA[0000] pulling image: rpc error: code = Unknown desc = failed to pull and unpack image "docker.io/test/invalid/image:latest": failed to resolve reference "docker.io/test/invalid/image:latest": failed to do request: Head "https://registry-1.docker.io/v2/test/invalid/image/manifests/latest": proxyconnect tcp: dial tcp: lookup invalidproxy: Temporary failure in name resolution
function check_proxy_config() {
    if [ -z "$CONTAINERD_VERSION" ]; then
       return
    fi

    logStep "Checking proxy configuration with Containerd"

    # Echo containerd Proxy config:
    local proxy_config_file="/etc/systemd/system/containerd.service.d/http-proxy.conf"
    if [ ! -f "$proxy_config_file" ]; then
        log "Skipping test. No HTTP proxy configuration found."
        return
    fi

    echo ""
    log "Proxy config:"
    grep -v -e '^\[Service\]' -e '^# Generated by kURL' "$proxy_config_file"
    echo ""

    if ! response=$(crictl pull test/invalid/image:latest 2>&1) && [[ $response =~ .*"proxy".* ]]; then
        logWarn "Proxy connection issues were identified:"
        error_message=$(echo "$response" | grep -oP '(?<=failed to do request: ).*' | sed -r 's/.*: //' | awk -F "\"" '{print $(NF-1)}' | sed -r 's/test\/invalid\/image:latest//')
        logWarn "$error_message"
        echo ""
        logWarn "Please review the proxy configuration and ensure that it is valid."
        logWarn "More info: https://kurl.sh/docs/install-with-kurl/proxy-installs"
        return
    fi
    logSuccess "Unable to identify proxy problems"
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
    # if the kubectl endpoint is already present in the no_proxy env we
    # can skip and move forward. this avoids adding the same ip address
    # multiple times and makes this function idempotent.
    if echo "$no_proxy" | grep -q "$HOST"; then
        return
    fi
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
