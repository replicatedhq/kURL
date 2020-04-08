function download_util_binaries() {
    curl -Ss -L $KURL_UTIL_BINARIES -o /tmp/kurl_util.tgz
    tar zxf /tmp/kurl_util.tgz -C /tmp

    BIN_SYSTEM_CONFIG=/tmp/kurl_util/bin/config
    BIN_YAMLUTIL=/tmp/kurl_util/bin/yamlutil
    BIN_DOCKER_CONFIG=/tmp/kurl_util/bin/docker-config
    BIN_SUBNET=/tmp/kurl_util/bin/subnet

    CONFIGURE_SELINUX_SCRIPT=/tmp/kurl_util/scripts/configure_selinux.sh
}

function apply_docker_config() {
    if [ -n "$PRESERVE_DOCKER_CONFIG" ]; then
        return
    fi

    if [ -z "$INSTALLER_SPEC_FILE" ] && [ -z "$INSTALLER_YAML" ]; then
        return
    fi

    cat > /tmp/vendor_kurl_installer_spec_docker.yaml <<EOL
${INSTALLER_YAML}
EOL

    $BIN_DOCKER_CONFIG -c /etc/docker/daemon.json -b /tmp/vendor_kurl_installer_spec_docker.yaml -o $INSTALLER_SPEC_FILE
}

function apply_selinux_config() {
## TODO: this needs merged yaml
#    cat > /tmp/vendor_kurl_installer_spec_selinux.yaml <<EOL
#${INSTALLER_YAML}
#EOL
    CONFIGURE_SELINUX_SCRIPT=$CONFIGURE_SELINUX_SCRIPT $BIN_SYSTEM_CONFIG -c selinux -g -y $INSTALLER_SPEC_FILE

    if [ -f "$CONFIGURE_SELINUX_SCRIPT" ]; then
        . $CONFIGURE_SELINUX_SCRIPT
        configure_selinux
    fi
}
