#!/bin/bash

set -e

DIR=.

# Magic begin: scripts are inlined for distribution. See "make build/join.sh"
. $DIR/scripts/Manifest
. $DIR/scripts/common/kurl.sh
. $DIR/scripts/common/addon.sh
. $DIR/scripts/common/common.sh
. $DIR/scripts/common/discover.sh
. $DIR/scripts/common/docker.sh
. $DIR/scripts/common/helm.sh
. $DIR/scripts/common/host-packages.sh
. $DIR/scripts/common/kubernetes.sh
. $DIR/scripts/common/object_store.sh
. $DIR/scripts/common/plugins.sh
. $DIR/scripts/common/preflights.sh
. $DIR/scripts/common/prompts.sh
. $DIR/scripts/common/proxy.sh
. $DIR/scripts/common/reporting.sh
. $DIR/scripts/common/rook.sh
. $DIR/scripts/common/rook-upgrade.sh
. $DIR/scripts/common/longhorn.sh
. $DIR/scripts/common/utilbinaries.sh
. $DIR/scripts/common/yaml.sh
. $DIR/scripts/distro/interface.sh
. $DIR/scripts/distro/kubeadm/distro.sh
# Magic end

function join() {
    if [ "$MASTER" = "1" ]; then
        logStep "Join Kubernetes master node"

        # this will stop all the control plane pods except etcd
        rm -f /etc/kubernetes/manifests/kube-*
        if commandExists docker ; then
            while docker ps 2>/dev/null | grep -q kube-apiserver ; do
                sleep 2
            done
        fi
        if commandExists crictl ; then
            while crictl ps 2>/dev/null | grep -q kube-apiserver ; do
                sleep 2
            done
        fi
        # delete files that need to be regenerated in case of load balancer address change
        rm -f /etc/kubernetes/*.conf
        rm -f /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.key
    else
        logStep "Join Kubernetes node"
    fi

    local kustomize_kubeadm_join="$DIR/kustomize/kubeadm/join"

    if [ "$MASTER" = "1" ]; then
        insert_patches_strategic_merge \
            $kustomize_kubeadm_join/kustomization.yaml \
            patch-control-plane.yaml
    fi

    local NODE_HOSTNAME=
    NODE_HOSTNAME=$(get_local_node_name)
    # if the hostname is overridden, patch the kubeadm config to use the overridden hostname
    if [ "$NODE_HOSTNAME" != "$(hostname | tr '[:upper:]' '[:lower:]')" ]; then
        render_yaml_file_2 "$kustomize_kubeadm_join/kubeadm-join-hostname.patch.tmpl.yaml" \
            > "$kustomize_kubeadm_join/kubeadm-join-hostname.patch.yaml"
        insert_patches_strategic_merge \
            $kustomize_kubeadm_join/kustomization.yaml \
            kubeadm-join-hostname.patch.yaml
    fi

    kubernetes_configure_pause_image "$kustomize_kubeadm_join"

    # Add kubeadm join patches from addons.
    for patch in $(ls -1 ${kustomize_kubeadm_join}-patches/* 2>/dev/null || echo); do
        patch_basename="$(basename $patch)"
        cp $patch $kustomize_kubeadm_join/$patch_basename
        insert_patches_strategic_merge \
            $kustomize_kubeadm_join/kustomization.yaml \
            $patch_basename
    done
    mkdir -p "$KUBEADM_CONF_DIR"
    kubectl kustomize $kustomize_kubeadm_join > $KUBEADM_CONF_DIR/kubeadm-join-raw.yaml
    render_yaml_file $KUBEADM_CONF_DIR/kubeadm-join-raw.yaml > $KUBEADM_CONF_FILE

    cp $KUBEADM_CONF_FILE $KUBEADM_CONF_DIR/kubeadm_conf_copy_in
    $DIR/bin/yamlutil -r -fp $KUBEADM_CONF_DIR/kubeadm_conf_copy_in -yp metadata
    mv $KUBEADM_CONF_DIR/kubeadm_conf_copy_in $KUBEADM_CONF_FILE

    # ensure that /etc/kubernetes/audit.yaml exists
    cp $kustomize_kubeadm_join/audit.yaml /etc/kubernetes/audit.yaml
    mkdir -p /var/log/apiserver

    set +e
    (set -x; kubeadm join --config "$KUBEADM_CONF_FILE" --ignore-preflight-errors=all)
    _status=$?
    set -e

    if [ "$_status" -ne "0" ]; then
        printf "${RED}Failed to join the kubernetes cluster.${NC}\n" 1>&2
        exit $_status
    fi

    if [ "$MASTER" = "1" ]; then
        exportKubeconfig

        kubectl label --overwrite node "$(get_local_node_name)" node-role.kubernetes.io/master=

        if [ "$KUBERNETES_CIS_COMPLIANCE" == "1" ]; then
            # create an 'etcd' user and group and ensure that it owns the etcd data directory (we don't care what userid these have, as etcd will still run as root)
            useradd etcd || true
            groupadd etcd || true
            chown -R etcd:etcd /var/lib/etcd
        fi

        logSuccess "Master node joined successfully"
    else
        logSuccess "Node joined successfully"
    fi

    if commandExists ekco_cleanup_bootstrap_internal_lb; then
        ekco_cleanup_bootstrap_internal_lb
    fi
}

outro() {
    printf "\n"
    printf "\t\t${GREEN}Installation${NC}\n"
    printf "\t\t${GREEN}  Complete ✔${NC}\n"
    if [ "$MASTER" = "1" ]; then
        printf "\n"
        kubeconfig_setup_outro
    fi
    printf "\n"
}

K8S_DISTRO=kubeadm

function main() {
    logStep "Running join with the argument(s): $*"
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
    prompt_license
    parse_kubernetes_target_version
    discover
    preflights
    join_prompts
    join_preflights # must come after joinPrompts as this function requires API_SERVICE_ADDRESS
    common_prompts
    journald_persistent
    configure_proxy
    configure_no_proxy
    ${K8S_DISTRO}_addon_for_each addon_fetch
    kubernetes_get_packages
    preflights_require_host_packages
    host_preflights "${MASTER:-0}" "1" "0"
    install_host_dependencies
    get_common
    setup_kubeadm_kustomize
    install_cri
    get_shared
    kubernetes_pre_init
    ${K8S_DISTRO}_addon_for_each addon_join
    helm_load
    kubernetes_host
    install_helm
    join
    outro
    package_cleanup

    popd_install_directory
}

# tee logs into /var/log/kurl/install-<date>.log and stdout
mkdir -p /var/log/kurl
LOGFILE="/var/log/kurl/join-$(date +"%Y-%m-%dT%H-%M-%S").log"
main "$@" 2>&1 | tee $LOGFILE
# it is required to return the exit status of the script
FINAL_RESULT="${PIPESTATUS[0]}"
sed -i "/\b\(password\)\b/d" $LOGFILE > /dev/null 2>&1
exit "$FINAL_RESULT"
