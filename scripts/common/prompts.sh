# Gather any additional information required from the user that could not be discovered and was not
# passed with a flag

function prompts() {
    if [ -z "$PRIVATE_ADDRESS" ]; then
        promptForPrivateIp
    fi
    # TODO public address? only required for adding SAN to K8s API server cert

    if [ "$NO_PROXY" != "1" ]; then
        if [ -z "$PROXY_ADDRESS" ]; then
            discoverProxy
        fi

        if [ -z "$PROXY_ADDRESS" ] && [ "$AIRGAP" != "1" ]; then
            promptForProxy
        fi

        if [ -n "$PROXY_ADDRESS" ]; then
            getNoProxyAddresses "$PRIVATE_ADDRESS" "$SERVICE_CIDR"
        fi
    fi
    return 0
}
