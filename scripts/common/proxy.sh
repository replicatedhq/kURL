
# DONE QA proxy from installer yaml
# DONE QA from override spec file
# DONE QA set in both yaml and local spec file
# TODO QA with single quotes
# TODO QA with double quotes
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
            echo "TODO REMOVE. Proxy address from installer spec file: $https_proxy"
            return
        fi
    fi
    local proxy=$(echo "$INSTALLER_YAML" | grep "proxyAddress:" | grep -o "http[^'\" ]*")
    if [ -n "$proxy" ]; then
        export https_proxy="$proxy"
        echo "TODO REMOVE. Proxy address from installer yaml: $https_proxy"
        return
    fi

    bail "Failed to make outbound https request and no proxy is configured."
}

# DONE QA validation fails
# DONE QA validation succeeds
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
    echo "TODO REMOVE: successfully validated proxy address $https_proxy"
}

function configure_no_proxy() {
    if [ -z "$PROXY_ADDRESS" ]; then
        return
    fi

	local addresses="localhost,127.0.0.1"

    if [ -n "$PRIVATE_ADDRESS" ]; then
        addresses="${addresses},${PRIVATE_ADDRESS}"
    fi
    if [ -n "$LOAD_BALANCER_ADDRESS" ]; then
        addresses="${addresses},${LOAD_BALANCER_ADDRESS}"
    fi
    if [ -n "$KUBERNETES_MASTER_ADDR" ]; then
        addresses="${addresses},${LOAD_BALANCER_ADDRESS}"
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
    echo "TODO REMOVE: exported no_proxy: $no_proxy"
}
