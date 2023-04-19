#!/bin/bash

# kubernetes_upgrade_preflight checks if kubernetes should be upgraded, and if so prompts the user
# to confirm the upgrade.
function kubernetes_upgrade_preflight() {
    local desired_version="$KUBERNETES_VERSION"

    if ! kubernetes_upgrade_should_upgrade_kubernetes ; then
        return
    fi

    local current_version=
    current_version="$(kubernetes_upgrade_discover_min_kubernetes_version)"

    if ! kubernetes_upgrade_prompt "$current_version" "$desired_version" ; then
        bail "Not upgrading Kubernetes"
    fi

    # use CURRENT_KUBERNETES_VERSION as that is the lowest version on this node
    if ! kubernetes_upgrade_storage_check "$CURRENT_KUBERNETES_VERSION" "$desired_version" ; then
        bail "Not upgrading Kubernetes"
    fi
}

# report_upgrade_kubernetes starts the kubernetes upgrade process.
function report_upgrade_kubernetes() {
    local desired_version="$KUBERNETES_VERSION"

    if ! kubernetes_upgrade_should_upgrade_kubernetes ; then
        enable_rook_ceph_operator
        return
    fi

    local current_version=
    current_version="$(kubernetes_upgrade_discover_min_kubernetes_version)"

    kubernetes_upgrade_report_upgrade_kubernetes "$current_version" "$desired_version"
}

# kubernetes_upgrade_discover_min_kubernetes_version will return the lowest kubernetes version on
# the cluster.
function kubernetes_upgrade_discover_min_kubernetes_version() {
    if [ -z "$CURRENT_KUBERNETES_VERSION" ]; then
        return
    fi

    # These versions are for the local primary
    semverParse "$CURRENT_KUBERNETES_VERSION"
    # shellcheck disable=SC2154
    local min_minor="$minor"
    # shellcheck disable=SC2154
    local min_patch="$patch"

    # Check for upgrades required on remote primaries
    for i in "${!KUBERNETES_REMOTE_PRIMARIES[@]}" ; do
        semverParse "${KUBERNETES_REMOTE_PRIMARY_VERSIONS[$i]}"
        if [ "$minor" -lt "$min_minor" ] || { [ "$minor" -eq "$min_minor" ] && [ "$patch" -lt "$min_patch" ]; }; then
            min_minor="$minor"
            min_patch="$patch"
        fi
    done

    # Check for upgrades required on secondaries
    for i in "${!KUBERNETES_SECONDARIES[@]}" ; do
        semverParse "${KUBERNETES_SECONDARY_VERSIONS[$i]}"
        if [ "$minor" -lt "$min_minor" ] || { [ "$minor" -eq "$min_minor" ] && [ "$patch" -lt "$min_patch" ]; }; then
            min_minor="$minor"
            min_patch="$patch"
        fi
    done

    echo "1.$min_minor.$min_patch"
}

# kubernetes_upgrade_report_upgrade_kubernetes reports the upgrade and starts the upgrade process.
function kubernetes_upgrade_report_upgrade_kubernetes() {
    local current_version="$1"
    local desired_version="$2"

    local from_version=
    from_version="$(common_upgrade_version_to_major_minor "$current_version")"

    local kubernetes_upgrade_version="v1.0.0" # if you change this code, change the version
    report_addon_start "kubernetes_upgrade_${from_version}_to_${desired_version}" "$kubernetes_upgrade_version"
    export REPORTING_CONTEXT_INFO="kubernetes_upgrade_${from_version}_to_${desired_version} $kubernetes_upgrade_version"
    kubernetes_upgrade "$current_version" "$desired_version"
    export REPORTING_CONTEXT_INFO=""
    report_addon_success "kubernetes_upgrade_${from_version}_to_${desired_version}" "$kubernetes_upgrade_version"
}

# kubernetes_upgrade upgrades will fetch the add-on and load the images for the upgrade and finally
# run the upgrade script.
function kubernetes_upgrade() {
    local current_version="$1"
    local desired_version="$2"

    disable_rook_ceph_operator

    # when invoked in a subprocess the failure of this function will not cause the script to exit
    # sanity check that the version is valid
    common_upgrade_step_versions "${STEP_VERSIONS[*]}" "$current_version" "$desired_version" 1>/dev/null

    logStep "Upgrading Kubernetes from $current_version to $desired_version"
    common_upgrade_print_list_of_minor_upgrades "$current_version" "$desired_version"
    echo "This may take some time."
    kubernetes_upgrade_addon_fetch "$current_version" "$desired_version"

    kubernetes_upgrade_prompt_missing_assets "$current_version" "$desired_version"

    kubernetes_upgrade_do_kubernetes_upgrade "$current_version" "$desired_version"

    enable_rook_ceph_operator

    logSuccess "Successfully upgraded Kubernetes from $current_version to $desired_version"
}

# kubernetes_upgrade_do_kubernetes_upgrade will step through each minor version upgrade from
# $current_version to $desired_version
function kubernetes_upgrade_do_kubernetes_upgrade() {
    local current_version="$1"
    local desired_version="$2"

    local step=
    while read -r step ; do
        if [ -z "$step" ] || [ "$step" = "0.0.0" ]; then
            continue
        fi
        if [ ! -d "$DIR/packages/kubernetes/$step/assets" ] ; then
            bail "Kubernetes version $step not found"
        fi
        logStep "Upgrading cluster to Kubernetes version $step"

        upgrade_kubernetes_local_master "$step"
        upgrade_kubernetes_remote_masters "$step"
        upgrade_kubernetes_workers "$step"

        # if this is not the last version in the loop, then delete the addon files to free up space
        if [ "$step" != "$desired_version" ]; then
            rm -f "$DIR/assets/kubernetes-$step.tar.gz"
            rm -rf "$DIR/packages/kubernetes/$step"
        fi

        # workaround as some code relies on this legacy label
        kubectl label --overwrite node --selector="node-role.kubernetes.io/control-plane" node-role.kubernetes.io/master=

        logSuccess "Cluster upgraded to Kubernetes version $step successfully"
    done <<< "$(common_upgrade_step_versions "${STEP_VERSIONS[*]}" "$current_version" "$desired_version")"

    if [ -n "$AIRGAP_MULTI_ADDON_PACKAGE_PATH" ]; then
        # delete the airgap package files to free up space
        rm -f "$AIRGAP_MULTI_ADDON_PACKAGE_PATH"
    fi
}

# kubernetes_upgrade_should_upgrade_kubernetes uses the KUBERNETES_UPGRADE environment variable set
# by discoverCurrentKubernetesVersion()
function kubernetes_upgrade_should_upgrade_kubernetes() {
    [ "$KUBERNETES_UPGRADE" = "1" ]
}

# kubernetes_upgrade_prompt prompts the user to confirm the kubernetes upgrade.
function kubernetes_upgrade_prompt() {
    local current_version="$1"
    local desired_version="$2"
    logWarn "$(printf "This script will upgrade Kubernetes from %s to %s." "$current_version" "$desired_version")"
    logWarn "Upgrading Kubernetes will take some time."
    printf "Would you like to continue? "

    confirmY
}

# kubernetes_upgrade_storage_check verifies that enough disk space exists for the kubernetes
# upgrade to complete successfully.
function kubernetes_upgrade_storage_check() {
    local current_version="$1"
    local desired_version="$2"

    local archive_size=
    archive_size="$(kubernetes_upgrade_required_archive_size "$current_version" "$desired_version")"

    # 2x archive size for extracted files
    # 3.5x archive size for container images
    common_upgrade_storage_check "$archive_size" 2 $((7/2)) "Kubernetes"
}

# kubernetes_upgrade_required_archive_size will determine the approximate size of the archive that
# will be downloaded to upgrade between the supplied kubernetes versions. The amount of space
# required within $KURL_INSTALL_DIRECTORY and /var/lib/containerd or /var/lib/docker can then be
# derived from this (2x archive size in kurl, 3.5x in containerd/docker).
function kubernetes_upgrade_required_archive_size() {
    local current_version="$1"
    local desired_version="$2"

    # 934.8 MB is the size of the kubernetes-1.26.3.tar.gz archive which is the largest archive
    local bundle_size_upper_bounds=935

    local total_archive_size=0
    local step=
    while read -r step ; do
        if [ -z "$step" ] || [ "$step" = "0.0.0" ]; then
            continue
        fi
        total_archive_size=$((total_archive_size + "$bundle_size_upper_bounds"))
    done <<< "$(common_upgrade_step_versions "${STEP_VERSIONS[*]}" "$current_version" "$desired_version")"

    echo "$total_archive_size"
}

# kubernetes_upgrade_addon_fetch will fetch all add-on versions from $current_version to
# $desired_version.
function kubernetes_upgrade_addon_fetch() {
    if [ "$AIRGAP" = "1" ]; then
        kubernetes_upgrade_addon_fetch_airgap "$@"
    else
        kubernetes_upgrade_addon_fetch_online "$@"
    fi
}

# kubernetes_upgrade_addon_fetch_online will fetch all add-on versions, one at a time, from
# $current_version to $desired_version.
function kubernetes_upgrade_addon_fetch_online() {
    local current_version="$1"
    local desired_version="$2"

    logStep "Downloading assets required for Kubernetes $current_version to $desired_version upgrade"

    local step=
    while read -r step ; do
        if [ -z "$step" ] || [ "$step" = "0.0.0" ]; then
            continue
        fi
        kubernetes_upgrade_addon_fetch_online_step "kubernetes" "$step"
    done <<< "$(common_upgrade_step_versions "${STEP_VERSIONS[*]}" "$current_version" "$desired_version")"

    logSuccess "Assets loaded for Kubernetes $current_version to $desired_version upgrade"
}

# kubernetes_upgrade_addon_fetch_online_step will fetch an individual add-on version.
function kubernetes_upgrade_addon_fetch_online_step() {
    local version="$2"

    kubernetes_get_host_packages_online "$version"
}

# kubernetes_upgrade_addon_fetch_airgap will prompt the user to fetch all add-on versions from
# $current_version to $desired_version.
function kubernetes_upgrade_addon_fetch_airgap() {
    local current_version="$1"
    local desired_version="$2"

     # the last version already included in the airgap bundle
    local version_less_one=
    version_less_one="$(common_upgrade_major_minor_less_one "$desired_version")"

    if kubernetes_upgrade_has_all_addon_version_packages "$current_version" "$version_less_one" ; then
        local node_missing_images=
        # shellcheck disable=SC2086
        node_missing_images=$(kubernetes_upgrade_nodes_missing_images "$current_version" "$version_less_one" "$(get_local_node_name)" "")

        if [ -z "$node_missing_images" ]; then
            log "All assets required for Kubernetes $current_version to $desired_version upgrade are present on this node"
            return
        fi
    fi

    logStep "Downloading assets required for Kubernetes $current_version to $desired_version upgrade"

    local addon_versions=()

    local step=
    while read -r step ; do
        if [ -z "$step" ] || [ "$step" = "0.0.0" ]; then
            continue
        fi
        addon_versions+=( "kubernetes-$step" )
    done <<< "$(common_upgrade_step_versions "${STEP_VERSIONS[*]}" "$current_version" "$version_less_one")"

    addon_fetch_multiple_airgap "${addon_versions[@]}"

    logSuccess "Assets loaded for Kubernetes $current_version to $desired_version upgrade"
}

# kubernetes_upgrade_has_all_addon_version_packages will return 1 if any add-on versions are
# missing that are necessary to perform the upgrade.
function kubernetes_upgrade_has_all_addon_version_packages() {
    local current_version="$1"
    local desired_version="$2"

    local step=
    while read -r step ; do
        if [ -z "$step" ] || [ "$step" = "0.0.0" ]; then
            continue
        fi
        if [ ! -f "packages/kubernetes/$step/Manifest" ]; then
            return 1
        fi
    done <<< "$(common_upgrade_step_versions "${STEP_VERSIONS[*]}" "$current_version" "$desired_version")"

    return 0
}

# kubernetes_upgrade_prompt_missing_assets prompts the user to run the command to load assets on
# all remote nodes before proceeding.
function kubernetes_upgrade_prompt_missing_assets() {
    local current_version="$1"
    local desired_version="$2"

    # online installs will load assets as part of the upgrade.sh script
    if [ "$AIRGAP" != "1" ]; then
        return
    fi

    # if we are only upgrading one minor version, then we don't need to prompt for assets as they
    # are part of the airgap bundle
    local version_less_one=
    version_less_one="$(common_upgrade_major_minor_less_one "$desired_version")"
    if [ "$(common_upgrade_compare_versions "$current_version" "$version_less_one")" -ge "0" ]; then
        return
    fi

    # always prompt on all nodes because assets are not only images
    common_prompt_task_missing_assets \
        "$(kubernetes_remote_nodes | awk '{ print $1 }')" \
        "$current_version" "$desired_version" "Kubernetes" "kubernetes-upgrade-load-assets"
}

# kubernetes_upgrade_nodes_missing_images will print a list of nodes that are missing images for
# the given kubernetes versions.
function kubernetes_upgrade_nodes_missing_images() {
    local current_version="$1"
    local desired_version="$2"
    local target_host="$3"
    local exclude_hosts="$4"

    local images_list=
    images_list="$(kubernetes_upgrade_images_list "$current_version" "$desired_version")"

    if [ -z "$images_list" ]; then
        return
    fi

    kubernetes_nodes_missing_images "$images_list" "$target_host" "$exclude_hosts"
}

# kubernetes_upgrade_images_list will print a list of images for the given kubernetes versions.
function kubernetes_upgrade_images_list() {
    local current_version="$1"
    local desired_version="$2"

    local images_list=

    local step=
    while read -r step ; do
        if [ -z "$step" ] || [ "$step" = "0.0.0" ]; then
            continue
        fi
        images_list="$(common_upgrade_merge_images_list \
            "$images_list" \
            "$(common_list_images_in_manifest_file "packages/kubernetes/$step/Manifest")" \
        )"
    done <<< "$(common_upgrade_step_versions "${STEP_VERSIONS[*]}" "$current_version" "$desired_version")"

    echo "$images_list"
}

# kubernetes_upgrade_tasks_load_assets is called from tasks.sh to load assets on remote notes for the
# kubernetes upgrade.
function kubernetes_upgrade_tasks_load_assets() {
    local from_version=
    local to_version=
    local airgap=
    common_upgrade_tasks_params "$@"

    common_task_require_param "from-version" "$from_version"
    common_task_require_param "to-version" "$to_version"

    if [ "$airgap" = "1" ]; then
        export AIRGAP=1
    fi

    export KUBECONFIG=/etc/kubernetes/admin.conf
    download_util_binaries

    if ! kubernetes_upgrade_storage_check "$from_version" "$to_version" ; then
        bail "Failed storage check"
    fi

    if ! kubernetes_upgrade_addon_fetch "$from_version" "$to_version" ; then
        bail "Failed to load assets"
    fi
}

function upgrade_kubeadm() {
    local k8sVersion=$1

    upgrade_maybe_remove_kubeadm_network_plugin_flag "$k8sVersion"

    cp -f "$DIR/packages/kubernetes/$k8sVersion/assets/kubeadm" /usr/bin/
    chmod a+rx /usr/bin/kubeadm
}

function upgrade_kubernetes_local_master() {
    local targetK8sVersion="$1"
    local nodeName=
    nodeName="$(get_local_node_name)"
    # shellcheck disable=SC2034
    local upgrading_kubernetes=true

    local nodeVersion=
    nodeVersion="$(kubectl get node --no-headers "$nodeName" 2>/dev/null | awk '{ print $5 }' | sed 's/v//')"
    if [ -z "$nodeVersion" ]; then
        nodeVersion="$(discover_local_kubernetes_version)"
    fi

    # check if the node is already at the target version
    semverCompare "$nodeVersion" "$targetK8sVersion"
    if [ "$SEMVER_COMPARE_RESULT" -ge "0" ]; then
        log "Node $nodeName is already at Kubernetes version $targetK8sVersion"
        return 0
    fi

    logStep "Upgrading local node to Kubernetes version $targetK8sVersion"

    kubernetes_load_images "$targetK8sVersion"

    upgrade_kubeadm "$targetK8sVersion"

    ( set -x; kubeadm upgrade plan "v${targetK8sVersion}" )
    printf "%bDrain local node and apply upgrade? %b" "$YELLOW" "$NC"
    confirmY
    kubernetes_drain "$nodeName"

    maybe_patch_node_cri_socket_annotation "$nodeName"

    spinner_kubernetes_api_stable
    # ignore-preflight-errors, do not fail on fail to pull images for airgap
    ( set -x; kubeadm upgrade apply "v$targetK8sVersion" --yes --force --ignore-preflight-errors=all )
    upgrade_etcd_image_18 "$targetK8sVersion"

    kubernetes_install_host_packages "$targetK8sVersion"
    systemctl daemon-reload
    systemctl restart kubelet

    spinner_kubernetes_api_stable
    kubectl uncordon "$nodeName"
    upgrade_delete_node_flannel "$nodeName"

    # force deleting the cache because the api server will use the stale API versions after kubeadm upgrade
    rm -rf "$HOME/.kube"

    spinner_until 120 kubernetes_node_has_version "$nodeName" "$targetK8sVersion"
    spinner_until 120 kubernetes_all_nodes_ready

    logSuccess "Local node upgraded to Kubernetes version $targetK8sVersion"
}

function upgrade_kubernetes_remote_masters() {
    local k8sVersion="$1"
    while read -r node ; do
        local nodeName=
        nodeName=$(echo "$node" | awk '{ print $1 }')
        logStep "Upgrading remote primary node $nodeName to Kubernetes version $k8sVersion"
        upgrade_kubernetes_remote_node "$node" "$k8sVersion"
        logSuccess "Remote primary node $nodeName upgraded to Kubernetes version $k8sVersion"
    done < <(try_1m kubernetes_remote_masters)
    spinner_until 120 kubernetes_all_nodes_ready
}

function upgrade_kubernetes_workers() {
    local k8sVersion="$1"
    while read -r node ; do
        local nodeName=
        nodeName=$(echo "$node" | awk '{ print $1 }')
        logStep "Upgrading remote worker node $nodeName to Kubernetes version $k8sVersion"
        upgrade_kubernetes_remote_node "$node" "$k8sVersion"
        logSuccess "Remote worker node $nodeName upgraded to Kubernetes version $k8sVersion"
    done < <(try_1m kubernetes_workers)
}

function upgrade_kubernetes_remote_node() {
    # one line of output from `kubectl get nodes`
    local node="$1"
    local targetK8sVersion="$2"

    local nodeName=
    nodeName=$(echo "$node" | awk '{ print $1 }')
    local nodeVersion=
    nodeVersion="$(echo "$node" | awk '{ print $5 }' | sed 's/v//' )"

    # check if the node is already at the target version
    semverCompare "$nodeVersion" "$targetK8sVersion"
    if [ "$SEMVER_COMPARE_RESULT" -ge "0" ]; then
        log "Node $nodeName is already at Kubernetes version $targetK8sVersion"
        return 0
    fi

    DOCKER_REGISTRY_IP=$(kubectl -n kurl get service registry -o=jsonpath='{@.spec.clusterIP}' 2>/dev/null || echo "")

    printf "\n%bDrain node $nodeName to prepare for upgrade? %b" "$YELLOW" "$NC"
    confirmY
    kubernetes_drain "$nodeName"

    local common_flags
    common_flags="${common_flags}$(get_docker_registry_ip_flag "${DOCKER_REGISTRY_IP}")"
    common_flags="${common_flags}$(get_additional_no_proxy_addresses_flag "${NO_PROXY_ADDRESSES}" "${NO_PROXY_ADDRESSES}")"
    common_flags="${common_flags}$(get_kurl_install_directory_flag "${KURL_INSTALL_DIRECTORY_FLAG}")"
    common_flags="${common_flags}$(get_remotes_flags)"

    printf "\n\n\tRun the upgrade script on remote node to proceed: %b%s%b\n\n" "$GREEN" "$nodeName" "$NC"

    if [ "$AIRGAP" = "1" ]; then
        printf "\t%bcat ./upgrade.sh | sudo bash -s airgap kubernetes-version=%s%s%b\n\n" "$GREEN" "$targetK8sVersion" "$common_flags" "$NC"
    else
        local prefix=
        prefix="$(build_installer_prefix "${INSTALLER_ID}" "${KURL_VERSION}" "${KURL_URL}" "${PROXY_ADDRESS}")"

        printf "\t%b %supgrade.sh | sudo bash -s kubernetes-version=%s%s%b\n\n" "$GREEN" "$prefix" "$targetK8sVersion" "$common_flags" "$NC"
    fi

    rm -rf "$HOME/.kube"

    spinner_until -1 kubernetes_node_has_version "$nodeName" "$targetK8sVersion"
    logSuccess "Kubernetes $targetK8sVersion detected on $nodeName"

    kubectl uncordon "$nodeName"
    upgrade_delete_node_flannel "$nodeName"
    spinner_until 120 kubernetes_all_nodes_ready
}

# In k8s 1.18 the etcd image tag changed from 3.4.3 to 3.4.3-0 but kubeadm does not rewrite the
# etcd manifest to use the new tag. When kubeadm init is run after the upgrade it switches to the
# tag and etcd takes a few minutes to restart, which often results in kubeadm init failing. This
# forces use of the updated tag so that the restart of etcd happens during upgrade when the node is
# already drained
function upgrade_etcd_image_18() {
    semverParse "$1"
    if [ "$minor" != "18" ]; then
        return 0
    fi
    local etcd_tag=
    etcd_tag=$(kubeadm config images list 2>/dev/null | grep etcd | awk -F':' '{ print $NF }')
    sed -i "s/image: k8s.gcr.io\/etcd:.*/image: k8s.gcr.io\/etcd:$etcd_tag/" /etc/kubernetes/manifests/etcd.yaml
}

# Workaround to fix "kubeadm upgrade node" error:
#   "error execution phase preflight: docker is required for container runtime: exec: "docker": executable file not found in $PATH"
# See https://github.com/kubernetes/kubeadm/issues/2364
function maybe_patch_node_cri_socket_annotation() {
    local node="$1"

    if [ -n "$DOCKER_VERSION" ] || [ -z "$CONTAINERD_VERSION" ]; then
        return
    fi

    if kubectl get node "$node" -ojsonpath='{.metadata.annotations.kubeadm\.alpha\.kubernetes\.io/cri-socket}' | grep -q "dockershim.sock" ; then
        kubectl annotate node "$node" --overwrite "kubeadm.alpha.kubernetes.io/cri-socket=unix:///run/containerd/containerd.sock"
    fi
}

# When there has been a migration from Docker to Containerd the kubeadm-flags.env file may contain
# the flag "--network-plugin" which has been removed as of Kubernetes 1.24 and causes the Kubelet
# to fail with "Error: failed to parse kubelet flag: unknown flag: --network-plugin". This function
# will remove the erroneous flag from the file.
function upgrade_maybe_remove_kubeadm_network_plugin_flag() {
    local k8sVersion=$1
    if [ "$(kubernetes_version_minor "$k8sVersion")" -lt "24" ]; then
        return
    fi
    sed -i 's/ \?--network-plugin \?[^ "]*//' /var/lib/kubelet/kubeadm-flags.env
}

# delete the flannel pod on the node so that CNI plugin binaries are recreated
# workaround for https://github.com/kubernetes/kubernetes/issues/115629
function upgrade_delete_node_flannel() {
    local node="$1"

    if kubectl get ns 2>/dev/null | grep -q kube-flannel; then
        kubectl delete pod -n kube-flannel --field-selector="spec.nodeName=$node"
    fi
}
