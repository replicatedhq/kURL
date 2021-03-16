
#!/bin/bash

set -e

DIR=.

# Magic begin: scripts are inlined for distribution. See "make build/upgrade.sh"
. $DIR/scripts/Manifest
. $DIR/scripts/common/addon.sh
. $DIR/scripts/common/common.sh
. $DIR/scripts/common/discover.sh
. $DIR/scripts/common/docker.sh
. $DIR/scripts/common/plugins.sh
. $DIR/scripts/common/kubernetes.sh
. $DIR/scripts/common/upgrade.sh
. $DIR/scripts/common/utilbinaries.sh
. $DIR/scripts/common/object_store.sh
. $DIR/scripts/common/preflights.sh
. $DIR/scripts/common/prompts.sh
. $DIR/scripts/common/proxy.sh
. $DIR/scripts/common/reporting.sh
. $DIR/scripts/common/rook.sh
. $DIR/scripts/common/yaml.sh
. $DIR/scripts/distro/interface.sh
. $DIR/scripts/distro/kubeadm/distro.sh
. $DIR/scripts/distro/rke2/distro.sh
# Magic end

maybe_upgrade() {
    local kubeletVersion="$(kubelet_version)"
    semverParse "$kubeletVersion"
    local kubeletMajor="$major"
    local kubeletMinor="$minor"
    local kubeletPatch="$patch"

    if [ -n "$HOSTNAME_CHECK" ]; then
        if [ "$HOSTNAME_CHECK" != "$(hostname)" ]; then
            bail "this script should be executed on host $HOSTNAME_CHECK"
        fi
    fi
    if [ "$kubeletVersion" == "$KUBENETES_VERSION" ]; then
        echo "Current installed kubelet version is same as requested upgrade, bailing"
        bail
    fi
    if [ "$kubeletMajor" -ne "$KUBERNETES_TARGET_VERSION_MAJOR" ]; then
        printf "Cannot upgrade from %s to %s\n" "$kubeletVersion" "$KUBERNETES_VERSION"
        return 1
    fi
    if [ "$kubeletMinor" -lt "$KUBERNETES_TARGET_VERSION_MINOR" ] || ([ "$kubeletMinor" -eq "$KUBERNETES_TARGET_VERSION_MINOR" ] && [ "$kubeletPatch" -lt "$KUBERNETES_TARGET_VERSION_PATCH" ]); then
        logStep "Kubernetes version v$kubeletVersion detected, upgrading node to version v$KUBERNETES_VERSION"

        upgrade_kubeadm "$KUBERNETES_VERSION"

        kubeadm upgrade node

        if kubernetes_is_master; then
            upgrade_etcd_image_18

            # scheduler and controller-manager kubeconfigs point to local API server in 1.19
            # but only on new installs, not upgrades. Force regeneration of the kubeconfigs
            # so that all 1.19 installs are consistent. The set-kubeconfig-server task run
            # after a load balancer address change relies on this behavior.
            # https://github.com/kubernetes/kubernetes/pull/94398
            if [ "$KUBERNETES_TARGET_VERSION_MINOR" -ge "19" ]; then
                rm -rf /etc/kubernetes/scheduler.conf
                kubeadm init phase kubeconfig scheduler --kubernetes-version "v${KUBERNETES_VERSION}"
                mv /etc/kubernetes/manifests/kube-scheduler.yaml /tmp/ && sleep 1 && mv /tmp/kube-scheduler.yaml /etc/kubernetes/manifests/
                rm /etc/kubernetes/controller-manager.conf
                kubeadm init phase kubeconfig controller-manager --kubernetes-version "v${KUBERNETES_VERSION}"
                mv /etc/kubernetes/manifests/kube-controller-manager.yaml /tmp/ && sleep 1 && mv /tmp/kube-controller-manager.yaml /etc/kubernetes/manifests/
            fi
        fi

        kubernetes_host

        logSuccess "Kubernetes node upgraded to $KUBERNETES_VERSION"

        rm -rf $HOME/.kube

        return
    fi
}

function outro() {
    printf "\n"
    printf "\t\t${GREEN}Upgrade${NC}\n"
    printf "\t\t${GREEN}  Complete ✔${NC}\n"
    printf "\n"
}

K8S_DISTRO=kubeadm

function main() {
    export KUBECONFIG=/etc/kubernetes/admin.conf
    require_root_user
    get_patch_yaml "$@"
    maybe_read_kurl_config_from_cluster

    if [ "$AIRGAP" = "1" ]; then
        move_airgap_assets
    fi
    pushd_install_directory

    proxy_bootstrap
    download_util_binaries
    get_machine_id
    merge_yaml_specs
    apply_bash_flag_overrides "$@"
    parse_yaml_into_bash_variables
    parse_kubernetes_target_version
    discover
    preflights
    journald_persistent
    configure_proxy
    configure_no_proxy
    host_preflights "${MASTER:-0}" "1" "1"
    ${K8S_DISTRO}_addon_for_each addon_pre_join
    install_cri
    get_shared
    maybe_upgrade
    install_host_dependencies
    ${K8S_DISTRO}_addon_for_each addon_join
    outro
    package_cleanup

    popd_install_directory
}

main "$@"
