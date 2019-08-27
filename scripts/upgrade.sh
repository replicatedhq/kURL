
#!/bin/bash

set -e

DIR=.

# Magic begin: scripts are inlined for distribution. See "make build/upgrade.sh"
. $DIR/scripts/Manifest
. $DIR/scripts/common/addon.sh
. $DIR/scripts/common/common.sh
. $DIR/scripts/common/discover.sh
. $DIR/scripts/common/docker.sh
. $DIR/scripts/common/flags.sh
. $DIR/scripts/common/kubernetes.sh
. $DIR/scripts/common/upgrade.sh
. $DIR/scripts/common/preflights.sh
. $DIR/scripts/common/prompts.sh
. $DIR/scripts/common/proxy.sh
. $DIR/scripts/common/rook.sh
. $DIR/scripts/common/yaml.sh
# Magic end

maybe_upgrade() {
    local kubeletVersion="$(kubelet_version)"
    semverParse "$kubeletVersion"
    local kubeletMajor="$major"
    local kubeletMinor="$minor"
    local kubeletPatch="$patch"

    if [ "$kubeletMajor" -ne "$KUBERNETES_TARGET_VERSION_MAJOR" ]; then
        printf "Cannot upgrade from %s to %s\n" "$kubeletVersion" "$KUBERNETES_VERSION"
        return 1
    fi
    if [ "$kubeletMinor" -lt "$KUBERNETES_TARGET_VERSION_MINOR" ] || ([ "$kubeletMinor" -eq "$KUBERNETES_TARGET_VERSION_MINOR" ] && [ "$kubeletPatch" -lt "$KUBERNETES_TARGET_VERSION_PATCH" ]); then
        logStep "Kubernetes version v$kubeletVersion detected, upgrading node to version v$KUBERNETES_VERSION"

        upgrade_kubeadm "$KUBERNETES_VERSION"

        case "$KUBERNETES_TARGET_VERSION_MINOR" in
            15)
                kubeadm upgrade node

                # correctly sets the --resolv-conf flag when systemd-resolver is running (Ubuntu 18)
                # https://github.com/kubernetes/kubeadm/issues/273
                if isMasterNode; then
                    kubeadm init phase kubelet-start
                fi

                kubernetes_host

                logSuccess "Kubernetes node upgraded to $KUBERNETES_VERSION"
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
    discover
    flags "$@"
    preflights
    maybe_upgrade
    outro
}

main "$@"
