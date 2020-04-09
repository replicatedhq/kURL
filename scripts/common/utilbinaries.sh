function download_util_binaries() {
    curl -Ss -L $KURL_UTIL_BINARIES -o /tmp/kurl_util.tgz
    tar zxf /tmp/kurl_util.tgz -C /tmp

    BIN_SYSTEM_CONFIG=/tmp/kurl_util/bin/config
    BIN_YAMLUTIL=/tmp/kurl_util/bin/yamlutil
    BIN_DOCKER_CONFIG=/tmp/kurl_util/bin/docker-config
    BIN_SUBNET=/tmp/kurl_util/bin/subnet
    BIN_INSTALLERMERGE=/tmp/kurl_util/bin/installermerge

    CONFIGURE_SELINUX_SCRIPT=/tmp/kurl_util/scripts/configure_selinux.sh
    CONFIGURE_FIREWALLD_SCRIPT=/tmp/kurl_util/scripts/configure_firewalld.sh
    CONFIGURE_IPTABLES_SCRIPT=/tmp/kurl_util/scripts/configure_iptables.sh
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
    CONFIGURE_SELINUX_SCRIPT=$CONFIGURE_SELINUX_SCRIPT $BIN_SYSTEM_CONFIG -c selinux -g -y $INSTALLER_SPEC_FILE
    if [ -f "$CONFIGURE_SELINUX_SCRIPT" ]; then
        . $CONFIGURE_SELINUX_SCRIPT
        configure_selinux
    fi
    CONFIGURE_SELINUX_SCRIPT=$CONFIGURE_SELINUX_SCRIPT $BIN_SYSTEM_CONFIG -c selinux -e -y $INSTALLER_SPEC_FILE
}

function apply_firewalld_config() {
    ## TODO: this needs merged yaml
    CONFIGURE_FIREWALLD_SCRIPT=$CONFIGURE_FIREWALLD_SCRIPT $BIN_SYSTEM_CONFIG -c firewalld -g -y $INSTALLER_SPEC_FILE
    if [ -f "$CONFIGURE_FIREWALLD_SCRIPT" ]; then
        . $CONFIGURE_FIREWALLD_SCRIPT
        configure_firewalld
    fi
    CONFIGURE_FIREWALLD_SCRIPT=$CONFIGURE_FIREWALLD_SCRIPT $BIN_SYSTEM_CONFIG -c firewalld -e -y $INSTALLER_SPEC_FILE
}

function apply_iptables_config() {
    ## TODO: this needs merged yaml
    CONFIGURE_IPTABLES_SCRIPT=$CONFIGURE_IPTABLES_SCRIPT $BIN_SYSTEM_CONFIG -c iptables -g -y $INSTALLER_SPEC_FILE
    if [ -f "$CONFIGURE_IPTABLES_SCRIPT" ]; then
        . $CONFIGURE_IPTABLES_SCRIPT
        configure_iptables
    fi
    CONFIGURE_IPTABLES_SCRIPT=$CONFIGURE_IPTABLES_SCRIPT $BIN_SYSTEM_CONFIG -c iptables -e -y $INSTALLER_SPEC_FILE
}
