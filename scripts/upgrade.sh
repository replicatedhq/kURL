
#!/bin/bash

set -e

DIR=.

# Magic begin: scripts are inlined for distribution. See "make build/upgrade.sh"
. $DIR/scripts/Manifest
. $DIR/scripts/common/addon.sh
. $DIR/scripts/common/common.sh
. $DIR/scripts/common/discover.sh
. $DIR/scripts/common/docker.sh
. $DIR/scripts/common/kubernetes.sh
. $DIR/scripts/common/upgrade.sh
. $DIR/scripts/common/utilbinaries.sh
. $DIR/scripts/common/object_store.sh
. $DIR/scripts/common/preflights.sh
. $DIR/scripts/common/prompts.sh
. $DIR/scripts/common/proxy.sh
. $DIR/scripts/common/rook.sh
. $DIR/scripts/common/yaml.sh
. $DIR/scripts/common/coredns.sh
# Magic end

maybe_upgrade() {
    local kubeletVersion="$(kubelet_version)"
    semverParse "$kubeletVersion"
    local kubeletMajor="$major"
    local kubeletMinor="$minor"
    local kubeletPatch="$patch"
    local minorVersionDifference=$(($KUBERNETES_TARGET_VERSION_MINOR - $kubeletMinor))
    local patchVersionDifference=$(($KUBERNETES_TARGET_VERSION_PATCH - $kubeletPatch))

    if [ -n "$HOSTNAME_CHECK" ]; then
        if [ "$HOSTNAME_CHECK" != "$(hostname)" ]; then
            bail "this script should be executed on host $HOSTNAME_CHECK"
        fi
    fi
    if [ "$kubeletVersion" == "$KUBENETES_VERSION" ]; then
        echo "Current installed kublet version is same as requested upgrade, bailing"
        bail
    fi
    if [ "$kubeletMajor" -ne "$KUBERNETES_TARGET_VERSION_MAJOR" ]; then
        printf "Cannot upgrade from %s to %s\n" "$kubeletVersion" "$KUBERNETES_VERSION"
        return 1
    fi
    if [ "$kubeletMinor" -lt "$KUBERNETES_TARGET_VERSION_MINOR" ] || ([ "$kubeletMinor" -eq "$KUBERNETES_TARGET_VERSION_MINOR" ] && [ "$kubeletPatch" -lt "$KUBERNETES_TARGET_VERSION_PATCH" ]); then
        logStep "Kubernetes version v$kubeletVersion detected, upgrading node to version v$KUBERNETES_VERSION"

        upgrade_kubeadm "$KUBERNETES_VERSION"

        case "$KUBERNETES_TARGET_VERSION_MINOR" in
            15 | 16 | 17)
                kubeadm upgrade node

                # correctly sets the --resolv-conf flag when systemd-resolver is running (Ubuntu 18)
                # https://github.com/kubernetes/kubeadm/issues/273
                if kubernetes_is_master; then
                    kubeadm init phase kubelet-start
                fi

                kubernetes_host
                systemctl daemon-reload
                systemctl restart kubelet

                logSuccess "Kubernetes node upgraded to $KUBERNETES_VERSION"

                rm -rf $HOME/.kube

                return
                ;;
        esac
    fi
}

function outro() {
    printf "\n"
    printf "\t\t${GREEN}Upgrade${NC}\n"
    printf "\t\t${GREEN}  Complete ✔${NC}\n"
    printf "\n"
}

function main() {
    export KUBECONFIG=/etc/kubernetes/admin.conf
    requireRootUser
    proxy_bootstrap
    download_util_binaries "$@"
    merge_yaml_specs
    apply_bash_flag_overrides "$@"
    parse_yaml_into_bash_variables
    parse_kubernetes_target_version
    discover
    preflights
    configure_proxy
    configure_no_proxy
    apply_docker_config
    get_shared
    maybe_upgrade
    outro
}

main "$@"
