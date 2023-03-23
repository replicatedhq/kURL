#!/bin/bash

set -e

DIR=.

# Magic begin: scripts are inlined for distribution. See "make build/upgrade.sh"
. $DIR/scripts/Manifest
. $DIR/scripts/common/kurl.sh
. $DIR/scripts/common/addon.sh
. $DIR/scripts/common/common.sh
. $DIR/scripts/common/discover.sh
. $DIR/scripts/common/docker.sh
. $DIR/scripts/common/helm.sh
. $DIR/scripts/common/host-packages.sh
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
. $DIR/scripts/common/rook-upgrade.sh
. $DIR/scripts/common/longhorn.sh
. $DIR/scripts/common/yaml.sh
. $DIR/scripts/distro/interface.sh
. $DIR/scripts/distro/kubeadm/distro.sh
# Magic end

maybe_upgrade() {
    local kubeletVersion="$(kubelet_version)"
    semverParse "$kubeletVersion"
    local kubeletMajor="$major"
    local kubeletMinor="$minor"
    local kubeletPatch="$patch"

    if [ -n "$HOSTNAME_CHECK" ]; then
        if [ "$HOSTNAME_CHECK" != "$(get_local_node_name)" ]; then
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

        ( set -x; kubeadm upgrade node )

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
    fi

    if commandExists ekco_cleanup_bootstrap_internal_lb; then
        ekco_cleanup_bootstrap_internal_lb
    fi
}

function outro() {
    printf "\n"
    printf "\t\t${GREEN}Upgrade${NC}\n"
    printf "\t\t${GREEN}  Complete ✔${NC}\n"
    # we delete $HOME/.kube on k8s upgrade so we need to add it back
    if [ "${MASTER:-0}" = "1" ]; then
        printf "\n"
        kubeconfig_setup_outro
    fi
    printf "\n"
}

K8S_DISTRO=kubeadm

function main() {
    logStep "Running upgrade with the argument(s): $*"
    export KUBECONFIG=/etc/kubernetes/admin.conf
    require_root_user
    # ensure /usr/local/bin/kubectl-plugin is in the path
    path_add "/usr/local/bin"
    kubernetes_init_hostname
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
    ${K8S_DISTRO}_addon_for_each addon_fetch
    kubernetes_get_packages
    preflights_require_host_packages
    host_preflights "${MASTER:-0}" "1" "1"
    install_host_dependencies
    get_common
    setup_kubeadm_kustomize
    install_cri
    get_shared
    ${K8S_DISTRO}_addon_for_each addon_join
    maybe_upgrade
    kubernetes_configure_pause_image_upgrade
    install_helm
    uninstall_docker
    outro
    package_cleanup

    popd_install_directory
}

# tee logs into /var/log/kurl/upgrade-<date>.log and stdout
mkdir -p /var/log/kurl
LOGFILE="/var/log/kurl/upgrade-$(date +"%Y-%m-%dT%H-%M-%S").log"
main "$@" 2>&1 | tee $LOGFILE
# it is required to return the exit status of the script
FINAL_RESULT="${PIPESTATUS[0]}"
sed -i "/\b\(password\)\b/d" $LOGFILE > /dev/null 2>&1
exit "$FINAL_RESULT"
