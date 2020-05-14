
# Need to peek at the yaml spec with bash to find if a proxy is needed to download the util binaries
# TODO QA proxy from installer yaml
# TODO QA from override spec file
# TODO QA set in both yaml and local spec file
# TODO QA with single quotes
# TODO QA with double quotes
function proxy_bootstrap() {
    if [ "$NO_PROXY" = "1" ]; then
        return
    fi
    if [ -n "$INSTALLER_SPEC_FILE" ]; then
        local overrideProxy=$(grep "proxyAddress:" "$INSTALLER_SPEC_FILE" | grep -o "http[^'\" ]*")
        if [ -n "$overrideProxy" ]; then
            export https_proxy="$overrideProxy"
            echo "TODO REMOVE. Proxy address from installer spec file: $https_proxy"
            return
        fi
    fi
    local proxy=$(cat "$INSTALLER_YAML" | grep -o "http[^'\" ]*")
    if [ -n "$proxy" ]; then
        export https_proxy="$proxy"
        echo "TODO REMOVE. Proxy address from installer yaml: $https_proxy"
        return
    fi
}

# TODO QA validation fails
# TODO QA validation succeeds
function configure_proxy() {
    if [ "$NO_PROXY" = "1" ]; then
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

    # kubeadm requires this in the environment to reach the K8s API server
    export no_proxy="$NO_PROXY_ADDRESSES"
}
