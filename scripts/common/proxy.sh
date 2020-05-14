
function configure_proxy() {
    if [ "$NO_PROXY" = "1" ]; then
        return
    fi
	if [ -z "$PROXY_ADDRESS" ]; then
		return
	fi

	# for curl to download packages
	export http_proxy="$PROXY_ADDRESS"

    curl --silent --fail https://api.replicated.com/market/v1/echo/ip

    # kubeadm requires this in the environment to reach the K8s API server
    export no_proxy="$NO_PROXY_ADDRESSES"
}
