
function sonobuoy() {
    sonobuoy_binary
}

function sonobuoy_join() {
    sonobuoy_binary
}

function sonobuoy_binary() {
    local src="${DIR}/addons/sonobuoy/${SONOBUOY_VERSION}"

    if ! kubernetes_is_master; then
        return 0
    fi

    if [ "${AIRGAP}" != "1" ]; then
        mkdir -p "${src}/assets"
        curl -L -o "${src}/assets/sonobuoy.tar.gz" "https://github.com/vmware-tanzu/sonobuoy/releases/download/v${SONOBUOY_VERSION}/sonobuoy_${SONOBUOY_VERSION}_linux_amd64.tar.gz"
    fi

    tar xzf "${src}/assets/sonobuoy.tar.gz" -C /usr/local/bin
}
