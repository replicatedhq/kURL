
function download_util_binaries() {
    if [ "$AIRGAP" != "1" ]; then
        # creates ./bin directory
        curl -Ss -L $DIST_URL/$KURL_BIN_UTILS_FILE | tar zx
    fi

    BIN_SYSTEM_CONFIG=./bin/config
    BIN_YAMLUTIL=./bin/yamlutil
    BIN_DOCKER_CONFIG=./bin/docker-config
    BIN_SUBNET=./bin/subnet
    BIN_INSTALLERMERGE=./bin/installermerge
    BIN_YAMLTOBASH=./bin/yamltobash

    mkdir -p /tmp/kurl-bin-utils/scripts
    CONFIGURE_SELINUX_SCRIPT=/tmp/kurl-bin-utils/scripts/configure_selinux.sh
    CONFIGURE_FIREWALLD_SCRIPT=/tmp/kurl-bin-utils/scripts/configure_firewalld.sh
    CONFIGURE_IPTABLES_SCRIPT=/tmp/kurl-bin-utils/scripts/configure_iptables.sh

    mkdir -p /tmp/kurl-bin-utils/specs
    MERGED_YAML_SPEC=/tmp/kurl-bin-utils/specs/merged.yaml

    PARSED_YAML_SPEC=/tmp/kurl-bin-utils/scripts/variables.sh
}

function parse_yaml_into_bash_variables() {
    $BIN_YAMLTOBASH -i $MERGED_YAML_SPEC -b $PARSED_YAML_SPEC

    source $PARSED_YAML_SPEC
    rm $PARSED_YAML_SPEC
}


function merge_yaml_specs() {
    if [ -z "$INSTALLER_SPEC_FILE" ] && [ -z "$INSTALLER_YAML" ]; then
        return
    fi

    if [ -z "$INSTALLER_YAML" ]; then
        cp -f $INSTALLER_SPEC_FILE $MERGED_YAML_SPEC
        return
    fi

    if [ -z "$INSTALLER_SPEC_FILE" ]; then
        cat > $MERGED_YAML_SPEC <<EOL
${INSTALLER_YAML}
EOL
        return
    fi

    cat > /tmp/vendor_kurl_installer_spec_docker.yaml <<EOL
${INSTALLER_YAML}
EOL

    $BIN_INSTALLERMERGE -m $MERGED_YAML_SPEC -b /tmp/vendor_kurl_installer_spec_docker.yaml -o $INSTALLER_SPEC_FILE
}

function apply_docker_config() {
    if [ -n "$PRESERVE_DOCKER_CONFIG" ]; then
        return
    fi

    if [ ! -f "$MERGED_YAML_SPEC" ]; then
        return
    fi

    $BIN_DOCKER_CONFIG -c /etc/docker/daemon.json -s $MERGED_YAML_SPEC
}

function apply_selinux_config() {
    if [ -n "$PRESERVE_SELINUX_CONFIG" ]; then
        return
    fi

    if [ ! -f "$MERGED_YAML_SPEC" ]; then
        return
    fi

    CONFIGURE_SELINUX_SCRIPT=$CONFIGURE_SELINUX_SCRIPT $BIN_SYSTEM_CONFIG -c selinux -g -y $MERGED_YAML_SPEC
    if [ -f "$CONFIGURE_SELINUX_SCRIPT" ]; then
        . $CONFIGURE_SELINUX_SCRIPT
        configure_selinux
    fi
    CONFIGURE_SELINUX_SCRIPT=$CONFIGURE_SELINUX_SCRIPT $BIN_SYSTEM_CONFIG -c selinux -e -y $MERGED_YAML_SPEC
}

function apply_firewalld_config() {
    if [ -n "$PRESERVE_FIREWALLD_CONFIG" ]; then
        return
    fi

    if [ ! -f "$MERGED_YAML_SPEC" ]; then
        return
    fi

    CONFIGURE_FIREWALLD_SCRIPT=$CONFIGURE_FIREWALLD_SCRIPT $BIN_SYSTEM_CONFIG -c firewalld -g -y $MERGED_YAML_SPEC
    if [ -f "$CONFIGURE_FIREWALLD_SCRIPT" ]; then
        . $CONFIGURE_FIREWALLD_SCRIPT
        configure_firewalld
    fi
    CONFIGURE_FIREWALLD_SCRIPT=$CONFIGURE_FIREWALLD_SCRIPT $BIN_SYSTEM_CONFIG -c firewalld -e -y $MERGED_YAML_SPEC
}

function apply_iptables_config() {
    if [ -n "$PRESERVE_IPTABLES_CONFIG" ]; then
        return
    fi

    if [ ! -f "$MERGED_YAML_SPEC" ]; then
        return
    fi

    CONFIGURE_IPTABLES_SCRIPT=$CONFIGURE_IPTABLES_SCRIPT $BIN_SYSTEM_CONFIG -c iptables -g -y $MERGED_YAML_SPEC
    if [ -f "$CONFIGURE_IPTABLES_SCRIPT" ]; then
        . $CONFIGURE_IPTABLES_SCRIPT
        configure_iptables
    fi
    CONFIGURE_IPTABLES_SCRIPT=$CONFIGURE_IPTABLES_SCRIPT $BIN_SYSTEM_CONFIG -c iptables -e -y $MERGED_YAML_SPEC
}
