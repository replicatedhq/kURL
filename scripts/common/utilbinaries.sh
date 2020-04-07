function download_util_binaries() {
    curl -Ss -L $KURL_UTIL_BINARIES -o /tmp/kurl_util.tgz
    tar zxf /tmp/kurl_util.tgz -C /tmp

    BIN_YAMLUTIL=/tmp/kurl_util/bin/yamlutil
    BIN_DOCKER_CONFIG=/tmp/kurl_util/bin/docker-config
    BIN_SUBNET=/tmp/kurl_util/bin/subnet
}

function apply_docker_config() {
    if [ -n "$PRESERVE_DOCKER_CONFIG" ]; then
        return
    fi

    if [ -z "$INSTALLER_SPEC_FILE" ] && [ -z "$INSTALLER_YAML" ]; then
        return
    fi

    cat > /tmp/vendor_kurl_installer_spec.yaml <<EOL
${INSTALLER_YAML}
EOL

    $BIN_DOCKER_CONFIG -c /etc/docker/daemon.json -b /tmp/vendor_kurl_installer_spec.yaml -o $INSTALLER_SPEC_FILE
}
