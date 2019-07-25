
function prepare() {
    loadIPVSKubeProxyModules

    exportProxy
    # kubeadm requires this in the environment to reach the K8s API server
    export no_proxy="$NO_PROXY_ADDRESSES"

    if [ "$SKIP_DOCKER_INSTALL" != "1" ]; then
        if [ "$OFFLINE_DOCKER_INSTALL" != "1" ]; then
            installDocker "$PINNED_DOCKER_VERSION" "$MIN_DOCKER_VERSION"

            semverParse "$PINNED_DOCKER_VERSION"
            if [ "$major" -ge "17" ]; then
                lockPackageVersion docker-ce
            fi
        else
            installDockerOffline
        fi
        checkDockerDriver
        checkDockerStorageDriver "$HARD_FAIL_ON_LOOPBACK"
    else
        requireDocker
    fi

    if [ "$NO_PROXY" != "1" ] && [ -n "$PROXY_ADDRESS" ]; then
        requireDockerProxy
    fi

    if [ "$RESTART_DOCKER" = "1" ]; then
        restartDocker
    fi

    if [ "$NO_PROXY" != "1" ] && [ -n "$PROXY_ADDRESS" ]; then
        checkDockerProxyConfig
    fi

    installKubernetesComponents "$KUBERNETES_VERSION"

    installCNIPlugins

    maybeGenerateBootstrapToken

    return 0
}
