
function sonobuoy() {
    sonobuoy_binary

    sonobuoy_airgap_maybe_tag_image "k8s.gcr.io/conformance:v${KUBERNETES_VERSION}" "registry.k8s.io/conformance:v${KUBERNETES_VERSION}"
    sonobuoy_airgap_maybe_tag_image "registry.k8s.io/conformance:v${KUBERNETES_VERSION}" "k8s.gcr.io/conformance:v${KUBERNETES_VERSION}"
}

function sonobuoy_already_applied() {
    sonobuoy_airgap_maybe_tag_image "k8s.gcr.io/conformance:v${KUBERNETES_VERSION}" "registry.k8s.io/conformance:v${KUBERNETES_VERSION}"
    sonobuoy_airgap_maybe_tag_image "registry.k8s.io/conformance:v${KUBERNETES_VERSION}" "k8s.gcr.io/conformance:v${KUBERNETES_VERSION}"
}

function sonobuoy_join() {
    sonobuoy_binary

    sonobuoy_airgap_maybe_tag_image "k8s.gcr.io/conformance:v${KUBERNETES_VERSION}" "registry.k8s.io/conformance:v${KUBERNETES_VERSION}"
    sonobuoy_airgap_maybe_tag_image "registry.k8s.io/conformance:v${KUBERNETES_VERSION}" "k8s.gcr.io/conformance:v${KUBERNETES_VERSION}"
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

function sonobuoy_airgap_maybe_tag_image() {
    if [ "$AIRGAP" != "1" ]; then
        return
    fi
    if [ -n "$DOCKER_VERSION" ]; then
        sonobuoy_docker_maybe_tag_image "$@"
    else
        sonobuoy_ctr_maybe_tag_image "$@"
    fi
}

function sonobuoy_docker_maybe_tag_image() {
    local src="$1"
    local dst="$2"
    if ! docker image inspect "$src" >/dev/null 2>&1 ; then
        # source image does not exist, will not tag
        return
    fi
    if docker image inspect "$dst" >/dev/null 2>&1 ; then
        # destination image exists, will not tag
        return
    fi
    docker image tag "$src" "$dst"
}

function sonobuoy_ctr_maybe_tag_image() {
    local src="$1"
    local dst="$2"
    if [ "$(ctr -n=k8s.io images list -q name=="$src" 2>/dev/null | wc -l)" = "0" ] ; then
        # source image does not exist, will not tag
        return
    fi
    if [ "$(ctr -n=k8s.io images list -q name=="$dst" 2>/dev/null | wc -l)" = "1" ] ; then
        # destination image exists, will not tag
        return
    fi
    ctr -n=k8s.io images tag "$src" "$dst"
}
