
function download_util_binaries() {
    get_patch_yaml "$@"

    if [ -z "$AIRGAP" ]; then
        curl -Ss -L $DIST_URL/$KURL_BIN_UTILS_FILE | tar zx
    fi

    BIN_SYSTEM_CONFIG=./bin/config
    BIN_YAMLUTIL=./bin/yamlutil
    BIN_DOCKER_CONFIG=./bin/docker-config
    BIN_SUBNET=./bin/subnet
    BIN_INSTALLERMERGE=./bin/installermerge
    BIN_YAMLTOBASH=./bin/yamltobash
    BIN_BASHTOYAML=./bin/bashmerge

    mkdir -p /tmp/kurl-bin-utils/scripts
    CONFIGURE_SELINUX_SCRIPT=/tmp/kurl-bin-utils/scripts/configure_selinux.sh
    CONFIGURE_FIREWALLD_SCRIPT=/tmp/kurl-bin-utils/scripts/configure_firewalld.sh
    CONFIGURE_IPTABLES_SCRIPT=/tmp/kurl-bin-utils/scripts/configure_iptables.sh

    mkdir -p /tmp/kurl-bin-utils/specs
    MERGED_YAML_SPEC=/tmp/kurl-bin-utils/specs/merged.yaml

    PARSED_YAML_SPEC=/tmp/kurl-bin-utils/scripts/variables.sh
}

function apply_bash_flag_overrides() {
    if [ -n "$1" ]; then
       temp_var="$@"
       $BIN_BASHTOYAML -c $MERGED_YAML_SPEC -f "$temp_var"
    fi
}

function parse_yaml_into_bash_variables() {
    $BIN_YAMLTOBASH -i $MERGED_YAML_SPEC -b $PARSED_YAML_SPEC

    source $PARSED_YAML_SPEC
    rm $PARSED_YAML_SPEC
}

parse_kubernetes_target_version() {
    semverParse "$KUBERNETES_VERSION"
    KUBERNETES_TARGET_VERSION_MAJOR="$major"
    KUBERNETES_TARGET_VERSION_MINOR="$minor"
    KUBERNETES_TARGET_VERSION_PATCH="$patch"
}

function get_patch_yaml() {
    while [ "$1" != "" ]; do
        _param="$(echo "$1" | cut -d= -f1)"
        _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
        case $_param in
            installer-spec-file)
                INSTALLER_SPEC_FILE="$_value"
                ;;
            airgap)
                AIRGAP="1"
                ;;
            cert-key|control-plane|docker-registry-ip|ha|kubeadm-token|kubeadm-token-ca-hash|kubernetes-master-address|kubernetes-version|preserve-docker-config|preserve-firewalld-config|preserve-iptables-config|preserve-selinux-config)
                ;;
            *)
                echo >&2 "Error: unknown parameter \"$_param\""
                exit 1
                ;;
        esac
        shift
    done
}

function merge_yaml_specs() {
    if [ -z "$INSTALLER_SPEC_FILE" ] && [ -z "$INSTALLER_YAML" ]; then
        echo "no yaml spec found"
        bail
    fi

    if [ -z "$INSTALLER_YAML" ]; then
        cp -f $INSTALLER_SPEC_FILE $MERGED_YAML_SPEC
        ONLY_APPLY_MERGED=1
        return
    fi

    if [ -z "$INSTALLER_SPEC_FILE" ]; then
        cat > $MERGED_YAML_SPEC <<EOL
${INSTALLER_YAML}
EOL
        ONLY_APPLY_MERGED=1
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

    if ! commandExists kubectl ; then
        restart_docker
        return
    fi

    OUTRO_NOTIFIY_TO_RESTART_DOCKER=1
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
