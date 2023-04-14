
function download_util_binaries() {
    if [ -z "$AIRGAP" ] && [ -n "$DIST_URL" ]; then
        package_download "${KURL_BIN_UTILS_FILE}"
        tar xzf "$(package_filepath "${KURL_BIN_UTILS_FILE}")"
    fi

    export BIN_KURL=$DIR/bin/kurl
    BIN_SYSTEM_CONFIG=$DIR/bin/config
    BIN_YAMLUTIL=$DIR/bin/yamlutil
    BIN_DOCKER_CONFIG=$DIR/bin/docker-config
    BIN_SUBNET=$DIR/bin/subnet
    BIN_INSTALLERMERGE=$DIR/bin/installermerge
    BIN_YAMLTOBASH=$DIR/bin/yamltobash
    BIN_BASHTOYAML=$DIR/bin/bashmerge
    BIN_PVMIGRATE=$DIR/bin/pvmigrate
    export BIN_ROOK_PVMIGRATOR=$DIR/bin/rook-pv-migrator

    mkdir -p /tmp/kurl-bin-utils/scripts
    CONFIGURE_SELINUX_SCRIPT=/tmp/kurl-bin-utils/scripts/configure_selinux.sh
    CONFIGURE_FIREWALLD_SCRIPT=/tmp/kurl-bin-utils/scripts/configure_firewalld.sh
    CONFIGURE_IPTABLES_SCRIPT=/tmp/kurl-bin-utils/scripts/configure_iptables.sh

    mkdir -p /tmp/kurl-bin-utils/specs
    MERGED_YAML_SPEC=/tmp/kurl-bin-utils/specs/merged.yaml
    VENDOR_PREFLIGHT_SPEC=/tmp/kurl-bin-utils/specs/vendor-preflight.yaml

    PARSED_YAML_SPEC=/tmp/kurl-bin-utils/scripts/variables.sh
}

function apply_bash_flag_overrides() {
    if [ -n "$1" ]; then
        $BIN_BASHTOYAML -c $MERGED_YAML_SPEC -f "$*"
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


function yaml_airgap() {
    # this is needed because the parsing for yaml comes after the first occasion where the $AIRGAP flag is used
    # we also account for if $INSTALLER_YAML spec has "$AIRGAP and "INSTALLER_SPEC_FILE spec turns it off"

    if [[ "$INSTALLER_YAML" =~ "airgap: true" ]]; then
        AIRGAP="1"
    fi

    if [ -n "$INSTALLER_SPEC_FILE" ]; then
        if grep -q "airgap: true" $INSTALLER_SPEC_FILE; then
            AIRGAP="1"
        fi
        if grep -q "airgap: false" $INSTALLER_SPEC_FILE; then
            AIRGAP=""
        fi
    fi
}

function get_patch_yaml() {
    while [ "$1" != "" ]; do
        _param="$(echo "$1" | cut -d= -f1)"
        _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
        case $_param in
            installer-spec-file)
                if [ -n "$_value" ]; then
                    INSTALLER_SPEC_FILE="$(readlink -f "$_value")" # resolve relative paths before we pushd
                fi
                ;;
            additional-no-proxy-addresses)
                ;;
            airgap)
                AIRGAP="1"
                ;;
            kurl-registry-ip)
                KURL_REGISTRY_IP="$_value"
                ;;
            cert-key)
                ;;
            control-plane)
                ;;
            docker-registry-ip)
                ;;
            ekco-enable-internal-load-balancer)
                ;;
            ha)
                ;;
            kubernetes-cis-compliance)
                ;;
            kubernetes-cluster-name)
                ;;
            aws-exclude-storage-class)
                ;;
            ignore-remote-load-images-prompt)
                ;;
            ignore-remote-upgrade-prompt)
                ;;
            container-log-max-size)
                ;;
            container-log-max-files)
                ;;
            kubeadm-token)
                ;;
            kubeadm-token-ca-hash)
                ;;
            kubernetes-load-balancer-use-first-primary)
                ;;
            kubernetes-master-address)
                ;;
            kubernetes-version)
                ;;
            kurl-install-directory)
                if [ -n "$_value" ]; then
                    KURL_INSTALL_DIRECTORY_FLAG="${_value}"
                    KURL_INSTALL_DIRECTORY="$(realpath ${_value})/kurl"
                fi
                ;;
            labels)
                NODE_LABELS="$_value"
                ;;
            load-balancer-address)
                ;;
            # Legacy Command
            preflight-ignore)
                ;;
            host-preflight-ignore)
                ;;
            # Legacy Command
            preflight-ignore-warnings)
                ;;
            host-preflight-enforce-warnings)
                ;;
            dismiss-host-packages-preflight) # possibly add this to the spec
                # shellcheck disable=SC2034
                KURL_DISMISS_HOST_PACKAGES_PREFLIGHT=1
                ;;
            preserve-docker-config)
                ;;
            preserve-firewalld-config)
                ;;
            preserve-iptables-config)
                ;;
            preserve-selinux-config)
                ;;
            public-address)
                ;;
            private-address)
                ;;
            yes)
                ASSUME_YES=1
                ;;
            auto-upgrades-enabled) # no longer supported
                ;;
            primary-host)
                if [ -z "$PRIMARY_HOST" ]; then
                    PRIMARY_HOST="$_value"
                else
                    PRIMARY_HOST="$PRIMARY_HOST,$_value"
                fi
                ;;
            secondary-host)
                if [ -z "$SECONDARY_HOST" ]; then
                    SECONDARY_HOST="$_value"
                else
                    SECONDARY_HOST="$SECONDARY_HOST,$_value"
                fi
                ;;
            # deprecated flag
            force-reapply-addons)
                logWarn "WARN: 'force-reapply-addon' option is deprecated"
                ;;
            skip-system-package-install)
                SKIP_SYSTEM_PACKAGE_INSTALL=1
                ;;
            # legacy command alias
            exclude-builtin-preflights)
                EXCLUDE_BUILTIN_HOST_PREFLIGHTS=1
                ;;
            exclude-builtin-host-preflights)
                EXCLUDE_BUILTIN_HOST_PREFLIGHTS=1
                ;;
            app-version-label)
                KOTSADM_APPLICATION_VERSION_LABEL="$_value"
                ;;
            ipv6)
                IPV6_ONLY=1
                ;;
            velero-restic-timeout)
                VELERO_RESTIC_TIMEOUT="$_value"
                ;;
            velero-server-flags)
                VELERO_SERVER_FLAGS="$_value"
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

    local previous_contents="$(cat /etc/docker/daemon.json 2>/dev/null | xargs)" # xargs trims whitespace

    $BIN_DOCKER_CONFIG -c /etc/docker/daemon.json -s $MERGED_YAML_SPEC

    if [ "$previous_contents" = "$(cat /etc/docker/daemon.json 2>/dev/null | xargs)" ]; then
        # if the spec has not changed do not restart docker
        return
    fi

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

    # Always exists on RHEL/CentOS and will be added on Ubuntu if selinux has been installed
    if [ ! -f "/etc/selinux/config" ]; then
        echo "SELinux is not installed: no configuration will be applied"
        return
    fi
    if [ $(getenforce) = "Disabled" ]; then
        echo "SELinux is disabled: no configuration will be applied"
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

function is_ha() {
    local master_count=
    master_count="$(maybe kubernetes_masters | wc -l)"
    if [ "$master_count" -gt 1 ]; then
        HA_CLUSTER=1
    fi
    if kubeadm_cluster_configuration >/dev/null 2>&1 ; then
        if [ -n "$(kubeadm_cluster_configuration | grep 'controlPlaneEndpoint:' | sed 's/controlPlaneEndpoint: \|"//g')" ]; then
            HA_CLUSTER=1
        fi
    fi
}

function get_addon_config() {
    local addon_name=$1
    addon_name=$(kebab_to_camel "$addon_name")

    $BIN_YAMLUTIL -j -fp $MERGED_YAML_SPEC -jf "spec.$addon_name"
}
