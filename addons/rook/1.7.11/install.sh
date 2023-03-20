# shellcheck disable=SC2148

function rook_pre_init() {
    local current_version
    current_version="$(rook_version)"

    export SKIP_ROOK_INSTALL
    if rook_should_skip_rook_install "$current_version" "$ROOK_VERSION" ; then
        SKIP_ROOK_INSTALL=1

        # If we do not upgrade Rook then the previous Rook version 1.0.4 is not compatible with Kubernetes 1.20+
        if [ "$KUBERNETES_TARGET_VERSION_MINOR" -ge 20 ] && [ "$current_version" = "1.0.4" ]; then
            export KUBERNETES_UPGRADE=0
            export KUBERNETES_VERSION
            KUBERNETES_VERSION=$(kubectl version --short | grep -i server | awk '{ print $3 }' | sed 's/^v*//')
            parse_kubernetes_target_version
            # There's no guarantee the packages from this version of Kubernetes are still available
            export SKIP_KUBERNETES_HOST=1
        fi
    fi

    if [ "${ROOK_BYPASS_UPGRADE_WARNING}" != "1" ]; then
        if [ "$SKIP_ROOK_INSTALL" != "1" ] && [ -n "$current_version" ] && [ "$current_version" != "$ROOK_VERSION" ]; then
            logWarn "WARNING: This installer will upgrade Rook to version ${ROOK_VERSION}."
            logWarn "Upgrading a Rook cluster is not without risk, including data loss."
            logWarn "The Rook cluster's storage may be unavailable for short periods during the upgrade process."
            log ""
            log "Would you like to continue? "
            if ! confirmN ; then
                logWarn "Will not upgrade rook-ceph cluster"
                SKIP_ROOK_INSTALL=1
            fi
        fi
    fi
}

function rook() {
    local src="${DIR}/addons/rook/${ROOK_VERSION}"

    rook_lvm2

    if [ "$SKIP_ROOK_INSTALL" = "1" ]; then
        local version
        version=$(rook_version)
        echo "Rook $version is already installed, will not upgrade to ${ROOK_VERSION}"
        rook_object_store_output
        return 0
    fi

    # delete old clusterrolebinding
    # see issue https://github.com/rook/rook/issues/6448
    kubectl delete --ignore-not-found clusterrolebinding rook-ceph-system-psp-users

    rook_operator_crds_deploy
    rook_operator_deploy
    rook_set_ceph_pool_replicas
    rook_ready_spinner # creating the cluster before the operator is ready fails
    rook_cluster_deploy

    rook_dashboard_ready_spinner
    export CEPH_DASHBOARD_URL=http://rook-ceph-mgr-dashboard.rook-ceph.svc.cluster.local:7000
    # Ceph v13+ requires login. Rook 1.0+ creates a secret in the rook-ceph namespace.
    local cephDashboardPassword
    cephDashboardPassword=$(kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode)
    if [ -n "$cephDashboardPassword" ]; then
        export CEPH_DASHBOARD_USER=admin
        export CEPH_DASHBOARD_PASSWORD="$cephDashboardPassword"
    fi

    if ! kubectl -n rook-ceph get pod -l app=rook-ceph-rgw -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running ; then
        semverParse "$ROOK_VERSION"
        # shellcheck disable=SC2154
        local rook_major_minor_version="${major}.${minor}"

        printf "\n\n${GREEN}Rook Ceph 1.4+ requires a secondary, unformatted block device attached to the host.${NC}\n"
        printf "${GREEN}If you are stuck waiting at this step for more than two minutes, you are either missing the device or it is already formatted.${NC}\n"
        printf "\t${GREEN} * If it is missing, attach it now and it will be picked up; or CTRL+C, attach, and re-start the installer${NC}\n"
        printf "\t${GREEN} * If the disk is attached, try wiping it using the recommended zap procedure: https://rook.io/docs/rook/v${rook_major_minor_version}/ceph-teardown.html#zapping-devices${NC}\n\n"
    fi

    printf "checking for attached secondary block device (awaiting rook-ceph RGW pod)\n"
    spinnerPodRunning rook-ceph rook-ceph-rgw-rook-ceph-store
    kubectl -n rook-ceph apply -f "$src/cluster/object-user.yaml"
    rook_object_store_output

    echo "Awaiting rook-ceph object store health"
    if ! spinner_until 120 rook_rgw_is_healthy ; then
        bail "Failed to detect healthy rook-ceph object store"
    fi

    # wait for all pods in the rook-ceph namespace to rollout
    log "Awaiting Rook rollout in rook-ceph namespace"
    rook_maybe_wait_for_rollout
}

function rook_join() {
    rook_lvm2
}

function rook_already_applied() {
    rook_object_store_output
    rook_set_ceph_pool_replicas
    $DIR/bin/kurl rook wait-for-health 120
    rook_maybe_wait_for_rollout
}

function rook_operator_crds_deploy() {
    local src="${DIR}/addons/rook/${ROOK_VERSION}"
    local dst="${DIR}/kustomize/rook"

    mkdir -p "${dst}"
    cp "$src/crds.yaml" "$dst/crds.yaml"

    # https://rook.io/docs/rook/v1.6/ceph-upgrade.html#1-update-common-resources-and-crds
    # NOTE: If your Rook-Ceph cluster was initially installed with rook v1.4 or lower, the above
    # command will return errors due to updates from Kubernetes’ v1beta1 Custom Resource
    # Definitions. The error will contain text similar to ... spec.preserveUnknownFields: Invalid
    # value....
    if ! kubectl apply -f "$dst/crds.yaml" 2>/dev/null ; then
        kubectl replace --save-config -f "$dst/crds.yaml"
        kubectl apply -f "$dst/crds.yaml"
    fi
}

function rook_operator_deploy() {
    local src="${DIR}/addons/rook/${ROOK_VERSION}/operator"
    local dst="${DIR}/kustomize/rook/operator"

    mkdir -p "${DIR}/kustomize/rook"
    rm -rf "$dst"
    cp -r "$src" "$dst"

    if [ "${K8S_DISTRO}" = "rke2" ]; then
        ROOK_HOSTPATH_REQUIRES_PRIVILEGED=1
        insert_patches_strategic_merge "$dst/kustomization.yaml" patches/deployment-rke2.yaml
    fi

    if [ "$ROOK_HOSTPATH_REQUIRES_PRIVILEGED" = "1" ]; then
        insert_patches_strategic_merge "$dst/kustomization.yaml" patches/deployment-privileged.yaml
    fi

    if [ "$KUBERNETES_TARGET_VERSION_MINOR" -lt "17" ]; then
        insert_resources "$dst/kustomization.yaml" priority-class.yaml
        insert_patches_strategic_merge "$dst/kustomization.yaml" patches/deployment-priority-class-16.yaml
    else
        insert_patches_strategic_merge "$dst/kustomization.yaml" patches/deployment-priority-class.yaml
    fi

    if [ "$IPV6_ONLY" = "1" ]; then
        sed -i "/\[global\].*/a\    ms bind ipv6 = true" "$dst/configmap-rook-config-override.yaml"
        sed -i "/\[global\].*/a\    ms bind ipv4 = false" "$dst/configmap-rook-config-override.yaml"
    fi

    # upgrade first before applying auth_allow_insecure_global_id_reclaim policy
    rook_maybe_auth_allow_insecure_global_id_reclaim

    kubectl -n rook-ceph apply -k "$dst/"
}

function rook_cluster_deploy() {
    local src="${DIR}/addons/rook/${ROOK_VERSION}/cluster"
    local dst="${DIR}/kustomize/rook/cluster"

    mkdir -p "${DIR}/kustomize/rook"
    rm -rf "$dst"
    cp -r "$src" "$dst"

    # resources
    render_yaml_file_2 "$dst/tmpl-rbd-storageclass.yaml" > "$dst/rbd-storageclass.yaml"
    insert_resources "$dst/kustomization.yaml" rbd-storageclass.yaml

    # conditional cephfs
    if [ "${ROOK_SHARED_FILESYSTEM_DISABLED}" != "1" ]; then
        mkdir -p "$dst/cephfs"
        touch "$dst/cephfs/kustomization.yaml"
        insert_resources "$dst/cephfs/kustomization.yaml" cephfs-storageclass.yaml
        insert_resources "$dst/cephfs/kustomization.yaml" filesystem.yaml
        render_yaml_file_2 "$src/cephfs/patches/tmpl-filesystem.yaml" > "$dst/cephfs/patches/filesystem.yaml"
        insert_patches_strategic_merge "$dst/cephfs/kustomization.yaml" patches/filesystem.yaml

        # MDS pod anti-affinity rules prevent them from co-scheduling on single-node installations
        local ready_node_count
        ready_node_count="$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready')"
        if [ "$ready_node_count" -le "1" ]; then
            insert_patches_strategic_merge "$dst/cephfs/kustomization.yaml" patches/filesystem-singlenode.yaml
        fi

        render_yaml_file_2 "$src/cephfs/patches/tmpl-filesystem-Json6902.yaml" > "$dst/cephfs/patches/filesystem-Json6902.yaml"
        insert_patches_json_6902 "$dst/cephfs/kustomization.yaml" patches/filesystem-Json6902.yaml ceph.rook.io v1 CephFilesystem rook-shared-fs rook-ceph

        insert_bases "$dst/kustomization.yaml" cephfs
    fi

    # patches
    render_yaml_file "$src/patches/tmpl-cluster.yaml" > "$dst/patches/cluster.yaml"
    insert_patches_strategic_merge "$dst/kustomization.yaml" patches/cluster.yaml
    render_yaml_file "$src/patches/tmpl-object.yaml" > "$dst/patches/object.yaml"
    insert_patches_strategic_merge "$dst/kustomization.yaml" patches/object.yaml
    render_yaml_file_2 "$src/patches/tmpl-rbd-storageclass.yaml" > "$dst/patches/rbd-storageclass.yaml"
    insert_patches_strategic_merge "$dst/kustomization.yaml" patches/rbd-storageclass.yaml
    if [ "$KUBERNETES_TARGET_VERSION_MINOR" -lt "17" ]; then
        sed -i 's/system-cluster-critical/rook-critical/g' "$dst/patches/cluster.yaml" "$dst/patches/object.yaml" "$dst/patches/filesystem.yaml"
    fi

    # Don't redeploy cluster - ekco may have made changes based on num of nodes in cluster
    # This must come after the yaml is rendered as it relies on dst.
    if kubernetes_resource_exists rook-ceph cephcluster rook-ceph ; then
        echo "Cluster rook-ceph already deployed"
        rook_cluster_deploy_upgrade

        # if we are enabling the shared filesystem for the first time, we need to create the filesystem
        if [ "${ROOK_SHARED_FILESYSTEM_DISABLED}" != "1" ] && ! kubernetes_resource_exists rook-ceph cephfilesystem rook-shared-fs ; then
            kubectl -n rook-ceph apply -k "$dst/cephfs/"
        fi
        return 0
    fi

    kubectl -n rook-ceph apply -k "$dst/"
}

function rook_cluster_deploy_upgrade() {
    # Prior to calling this function the following steps have been taken in the upgrade process:
    # 1. https://rook.io/docs/rook/v1.6/ceph-upgrade.html#1-update-common-resources-and-crds
    #    rook_operator_crds_deploy
    #    rook_operator_deploy
    # 2. https://rook.io/docs/rook/v1.5/ceph-upgrade.html#2-update-ceph-csi-versions
    #    Not needed, using default CSI images
    # 3. https://rook.io/docs/rook/v1.6/ceph-upgrade.html#3-update-the-rook-operator
    #    rook_operator_deploy

    local ceph_image="quay.io/ceph/ceph:v16.2.7"
    local ceph_version=
    ceph_version="$(echo "${ceph_image}" | awk 'BEGIN { FS=":v" } ; {print $2}')"

    if rook_ceph_version_deployed "${ceph_version}" ; then
        echo "Cluster rook-ceph up to date"
        rook_patch_insecure_clients

        rook_cluster_deploy_upgrade_flexvolumes_to_csi
        return 0
    fi

    if kubernetes_resource_exists rook-ceph cephfilesystem rook-shared-fs ; then
        # When upgrading we need both MDS pods and anti-affinity rules prevent them from co-scheduling on single-node installations
        local ready_node_count
        ready_node_count="$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready')"
        if [ "$ready_node_count" -le "1" ]; then
            rook_cephfilesystem_patch_singlenode
        fi
    fi

    # 4. https://rook.io/docs/rook/v1.6/ceph-upgrade.html#4-wait-for-the-upgrade-to-complete
    echo "Awaiting rook-ceph operator"
    if ! "$DIR"/bin/kurl rook wait-for-rook-version "$ROOK_VERSION" --timeout=1200 ; then
        logWarn "Timeout waiting for Rook version rolled out"
        logStep "Checking Rook versions and replicas"
        kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{.metadata.name}{"  \treq/upd/avl: "}{.spec.replicas}{"/"}{.status.updatedReplicas}{"/"}{.status.readyReplicas}{"  \trook-version="}{.metadata.labels.rook-version}{"\n"}{end}'
        local rook_versions=
        rook_versions="$(kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"rook-version="}{.metadata.labels.rook-version}{"\n"}{end}' | sort | uniq)"
        if [ -n "${rook_versions}" ] && [ "$(echo "${rook_versions}" | wc -l)" -gt "1" ]; then
            logWarn "Detected multiple Rook versions"
            logWarn "${rook_versions}"
            logWarn "Failed to verify the Rook upgrade, multiple Rook versions detected"
        fi
    fi

    # 5. https://rook.io/docs/rook/v1.6/ceph-upgrade.html#5-verify-the-updated-cluster
    echo "Awaiting Ceph healthy"

    # CRD changes makes rook to restart and it takes time to reconcile
    if ! $DIR/bin/kurl rook wait-for-health 600 ; then
        kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
        bail "Refusing to update cluster rook-ceph, Ceph is not healthy"
    fi

    # https://rook.io/docs/rook/v1.6/ceph-upgrade.html#ceph-version-upgrades
    logStep "Upgrading rook-ceph cluster"

    # https://rook.io/docs/rook/v1.6/ceph-upgrade.html#1-update-the-main-ceph-daemons

    kubectl -n rook-ceph patch cephcluster/rook-ceph --type='json' -p='[{"op": "replace", "path": "/spec/cephVersion/image", "value":"'"${ceph_image}"'"}]'

    # https://rook.io/docs/rook/v1.6/ceph-upgrade.html#2-wait-for-the-daemon-pod-updates-to-complete
    if ! $DIR/bin/kurl rook wait-for-ceph-version "${ceph_version}-0" --timeout=1200 ; then
        logWarn "Timeout waiting for Ceph version to be rolled out"
        log "Checking Ceph versions and replicas"
        kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{.metadata.name}{"  \treq/upd/avl: "}{.spec.replicas}{"/"}{.status.updatedReplicas}{"/"}{.status.readyReplicas}{"  \tceph-version="}{.metadata.labels.ceph-version}{"\n"}{end}'
        local ceph_versions_found=
        ceph_versions_found="$(kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"ceph-version="}{.metadata.labels.ceph-version}{"\n"}{end}' | sort | uniq)"
        if [ -n "${ceph_versions_found}" ] && [ "$(echo "${ceph_versions_found}" | wc -l)" -gt "1" ]; then
            # Ignore the RookCeph issue scenario when the version is not set
            if [ "$(echo "${ceph_versions_found}" | wc -l)" == "2" ] && [ "$(echo "${ceph_versions_found}" | grep "0.0.0-0")" ]; then
                log "Found two ceph versions but one of them is 0.0.0-0 which will be ignored"
                echo "${ceph_versions_found}"
            else
                logWarn "Detected multiple Ceph versions"
                logWarn "${ceph_versions_found}"
                logWarn "Failed to verify the Ceph upgrade, multiple Ceph versions detected"
            fi
        fi

        if [[ "$(echo "${ceph_versions_found}")" == *"${ceph_version}"* ]]; then
            logWarn "Ceph version found ${ceph_versions_found}. New Ceph version ${ceph_version} failed to deploy"
        fi
        bail "New Ceph version failed to deploy"
    fi

    rook_patch_insecure_clients

    # https://rook.io/docs/rook/v1.6/ceph-upgrade.html#3-verify-the-updated-cluster

    echo "Awaiting Ceph healthy"

    if ! $DIR/bin/kurl rook wait-for-health 300 ; then
        kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
        bail "Failed to verify the updated cluster, Ceph is not healthy"
    fi

    rook_cluster_deploy_upgrade_flexvolumes_to_csi

    logStep "Checking if the Rook-Ceph cluster upgrade completed successfully"
    verify_rook_updated_cluster
    logSuccess "Rook-Ceph cluster upgraded successfully"
}

# Before to finish end report that the upgrade was done with success ensure that
# only on rook version is found and the ceph status
# https://rook.io/docs/rook/v1.9/ceph-upgrade.html#3-verify-the-updated-cluster
function verify_rook_updated_cluster() {
    log "Verifying Rook Version Deployed"
    if ! "$DIR"/bin/kurl rook wait-for-rook-version "$ROOK_VERSION" --timeout=1200 ; then
        logWarn "Timeout awaiting Rook version"
        log "Rook versions and replicas"
        kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{.metadata.name}{"  \treq/upd/avl: "}{.spec.replicas}{"/"}{.status.updatedReplicas}{"/"}{.status.readyReplicas}{"  \trook-version="}{.metadata.labels.rook-version}{"\n"}{end}'
        local rook_versions=
        rook_versions="$(kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"rook-version="}{.metadata.labels.rook-version}{"\n"}{end}' | sort | uniq)"
        if [ -n "${rook_versions}" ] && [ "$(echo "${rook_versions}" | wc -l)" -gt "1" ]; then
            logWarn "Detected multiple Rook versions"
            logWarn "${rook_versions}"
            bail "Failed to verify the Rook upgrade, multiple Rook versions detected"
        fi
    fi

    log "Verifying Ceph version ${ceph_version} deployed"
    if ! "$DIR"/bin/kurl rook wait-for-ceph-version "${ceph_version}-0" --timeout=1200 ; then
        logWarn "Timeout waiting for Ceph version to be rolled out"
        log "Checking Ceph versions and replicas"
        kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{.metadata.name}{"  \treq/upd/avl: "}{.spec.replicas}{"/"}{.status.updatedReplicas}{"/"}{.status.readyReplicas}{"  \tceph-version="}{.metadata.labels.ceph-version}{"\n"}{end}'
        local ceph_versions_found=
        ceph_versions_found="$(kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"ceph-version="}{.metadata.labels.ceph-version}{"\n"}{end}' | sort | uniq)"
        if [ -n "${ceph_versions_found}" ] && [ "$(echo "${ceph_versions_found}" | wc -l)" -gt "1" ]; then
            # Ignore the RookCeph issue scenario when the version is not set
            if [ "$(echo "${ceph_versions_found}" | wc -l)" == "2" ] && [ "$(echo "${ceph_versions_found}" | grep "0.0.0-0")" ]; then
                log "Found two ceph versions but one of them is 0.0.0-0 which will be ignored"
                echo "${ceph_versions_found}"
            else
                logWarn "Detected multiple Ceph versions"
                logWarn "${ceph_versions_found}"
                bail "Failed to verify the Ceph upgrade, multiple Ceph versions detected"
            fi
        fi

        if [[ "$(echo "${ceph_versions_found}")" == *"${ceph_version}"* ]]; then
            bail "Ceph version found ${ceph_versions_found}. New Ceph version ${ceph_version} failed to deploy"
        fi
        bail "New Ceph version ${ceph_version} failed to deploy"
    fi

    log "Verifying Ceph status"
    if ! $DIR/bin/kurl rook wait-for-health 300 ; then
        kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
        bail "Failed to verify the updated cluster, Ceph is not healthy"
    fi
}

# rook_cluster_deploy_upgrade_flexvolumes_to_csi will check if the previous storageclass is using
# the flex volume provisioner (if this is an upgrade from 1.0.4) and will deploy a new storageclass
# with the CSI provisioner following this guide:
# https://rook.io/docs/rook/v1.7/flex-to-csi-migration.html
function rook_cluster_deploy_upgrade_flexvolumes_to_csi() {
    local src="$DIR/addons/rook/$ROOK_VERSION/cluster"
    local dst="$DIR/kustomize/rook/cluster"

    local src_sc="${STORAGE_CLASS:-default}"
    local tmp_sc=rook-ceph-tmp

    local rook_did_scale_down_ekco=0
    local rook_did_scale_down_prometheus=0

    # if the "default" storage class exists and it is still using the flex volume provisioner
    if [ "$(kubectl get sc "$src_sc" --ignore-not-found -o jsonpath='{.provisioner}')" = "ceph.rook.io/block" ]; then
        # patch the existing storage class to not be the default
        kubectl patch storageclass "$src_sc" -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

        # deploy a new storage class with the CSI provisioner
        rook_cluster_deploy_upgrade_create_storageclass "$tmp_sc"

        if [ "$rook_did_scale_down_ekco" != "1" ]; then
            rook_scale_down_ekco
        fi
        if [ "$rook_did_scale_down_prometheus" != "1" ]; then
            rook_scale_down_prometheus
        fi

        # run the actual flex volumes to csi volumes migration
        rook_cluster_deploy_upgrade_pvmigrator "$src_sc" "$tmp_sc"

        kubectl delete sc "$src_sc"
    fi

    # if there is still a temp storage class, it means we have not finished the migration
    if kubectl get sc "$tmp_sc" >/dev/null 2>&1 ; then
        # migrate a second time effectively renaming the temp storageclass back to "default"
        rook_cluster_deploy_upgrade_create_storageclass "$src_sc"

        if [ "$rook_did_scale_down_ekco" != "1" ]; then
            rook_scale_down_ekco
        fi
        if [ "$rook_did_scale_down_prometheus" != "1" ]; then
            rook_scale_down_prometheus
        fi

        rook_cluster_deploy_upgrade_pvmigrator "$tmp_sc" "$src_sc"

        # delete the temp storageclass
        kubectl delete sc "$tmp_sc"
    fi

    if [ "$rook_did_scale_down_ekco" = "1" ]; then
        rook_scale_up_ekco
    fi
    if [ "$rook_did_scale_down_prometheus" = "1" ]; then
        rook_scale_up_prometheus
    fi
}

# rook_cluster_deploy_upgrade_create_storageclass will render the necessary resources and create a
# storageclass
function rook_cluster_deploy_upgrade_create_storageclass() {
    local dst_sc="$1"

    local kustomize_dir="$dst/rbd-storageclass-$dst_sc"

    mkdir -p "$kustomize_dir/patches/"
    echo "" > "$kustomize_dir/kustomization.yaml" # clear the file
    local o_storage_class="$STORAGE_CLASS"
    export STORAGE_CLASS="$dst_sc"
    render_yaml_file_2 "$src/tmpl-rbd-storageclass.yaml" > "$dst/rbd-storageclass.yaml"
    render_yaml_file_2 "$src/patches/tmpl-rbd-storageclass.yaml" > "$dst/patches/rbd-storageclass.yaml"
    STORAGE_CLASS="$o_storage_class" # restore the original value
    cp "$dst/rbd-storageclass.yaml" "$kustomize_dir/rbd-storageclass.yaml"
    cp "$dst/patches/rbd-storageclass.yaml" "$kustomize_dir/patches/rbd-storageclass.yaml"
    insert_resources "$kustomize_dir/kustomization.yaml" rbd-storageclass.yaml
    insert_patches_strategic_merge "$kustomize_dir/kustomization.yaml" patches/rbd-storageclass.yaml
    kubectl apply -k "$kustomize_dir/"
}

# rook_cluster_deploy_upgrade_pvmigrator will invoke the kurl rook flexvolume-to-csi command to run
# the actual flex volumes to csi volumes migration
function rook_cluster_deploy_upgrade_pvmigrator() {
    local src_sc="$1"
    local dst_sc="$2"

    logStep "Migrating Rook Flex volumes to CSI volumes"
    local node_name=
    node_name="$(get_local_node_name)"
    local bin_path=
    bin_path="$(realpath "$BIN_ROOK_PVMIGRATOR")"

    ( set -x;
    "$BIN_KURL" rook flexvolume-to-csi \
        --source-sc "$src_sc" \
        --destination-sc "$dst_sc" \
        --node "$node_name" \
        --pv-migrator-bin-path "$bin_path" \
        --ceph-migrator-image "rook/ceph:v$ROOK_VERSION" )
    logSuccess "Rook Flex volumes to CSI volumes migrated successfully"
}

# rook_scale_down_ekco will scale down ekco to 0 replicas
function rook_scale_down_ekco() {
    if ! kubernetes_resource_exists kurl deployment ekc-operator ; then
        return
    fi

    if [ "$(kubectl -n kurl get deployments ekc-operator -o jsonpath='{.spec.replicas}')" = "0" ]; then
        return
    fi

    kubectl -n kurl scale deployment ekc-operator --replicas=0
    rook_did_scale_down_ekco=1 # local to caller
    log "Waiting for ekco pods to be removed"
    if ! spinner_until 120 ekco_pods_gone; then
        logFail "Unable to scale down ekco operator"
        return 1
    fi
}

# rook_scale_up_ekco will scale up ekco to 1 replica
function rook_scale_up_ekco() {
    if ! kubernetes_resource_exists kurl deployment ekc-operator ; then
        return
    fi

    kubectl -n kurl scale deployment ekc-operator --replicas=1
}

# rook_scale_down_prometheus will scale down prometheus to 0 replicas
function rook_scale_down_prometheus() {
    if ! kubernetes_resource_exists monitoring prometheus k8s ; then
        return
    fi

    if [ "$(kubectl -n monitoring get prometheus k8s -o jsonpath='{.spec.replicas}')" = "0" ]; then
        return
    fi

    kubectl -n monitoring patch prometheus k8s --type='json' --patch '[{"op": "replace", "path": "/spec/replicas", value: 0}]'
    rook_did_scale_down_prometheus=1 # local to caller
    log "Waiting for prometheus pods to be removed"
    spinner_until 300 prometheus_pods_gone
}

# rook_scale_up_prometheus will scale up prometheus replicas to 2
function rook_scale_up_prometheus() {
    if ! kubernetes_resource_exists monitoring prometheus k8s ; then
        return
    fi

    kubectl -n monitoring patch prometheus k8s --type='json' --patch '[{"op": "replace", "path": "/spec/replicas", value: 2}]'
}

function rook_dashboard_ready_spinner() {
    echo "Awaiting rook-ceph dashboard password"

    spinner_until 300 kubernetes_resource_exists rook-ceph secret rook-ceph-dashboard-password
}

function rook_ready_spinner() {
    echo "Awaiting rook-ceph pods"

    spinner_until 60 kubernetes_resource_exists rook-ceph deployment rook-ceph-operator
    spinner_until 60 kubernetes_resource_exists rook-ceph daemonset rook-discover
    spinner_until 300 deployment_fully_updated rook-ceph rook-ceph-operator
    spinner_until 60 daemonset_fully_updated rook-ceph rook-discover
}

# rook_ceph_version_deployed check that there is only one ceph-version reported across the cluster
function rook_ceph_version_deployed() {
    local ceph_version="$1"
    # wait for our version to start reporting
    if ! kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"ceph-version="}{.metadata.labels.ceph-version}{"\n"}{end}' | grep -q "${ceph_version}" ; then
        return 1
    fi
    # wait for our version to be the only one reporting
    if [ "$(kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"ceph-version="}{.metadata.labels.ceph-version}{"\n"}{end}' | sort | uniq | wc -l)" != "1" ]; then
        return 1
    fi
    # sanity check
    if ! kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"ceph-version="}{.metadata.labels.ceph-version}{"\n"}{end}' | grep -q "${ceph_version}" ; then
        return 1
    fi
    return 0
}

# CEPH_POOL_REPLICAS is undefined when this function is called unless set explicitly with a flag.
# If set by flag use that value.
# Else if the replicapool cephbockpool CR in the rook-ceph namespace is found, set CEPH_POOL_REPLICAS to that.
# Then increase up to 3 based on the number of ready nodes found.
# The ceph-pool-replicas flag will override any value set here.
function rook_set_ceph_pool_replicas() {
    if [ -n "$CEPH_POOL_REPLICAS" ]; then
        return 0
    fi
    CEPH_POOL_REPLICAS=1
    set +e
    local discoveredCephPoolReplicas
    discoveredCephPoolReplicas=$(kubectl -n rook-ceph get cephblockpool replicapool -o jsonpath="{.spec.replicated.size}" 2>/dev/null)
    if [ -n "$discoveredCephPoolReplicas" ]; then
        CEPH_POOL_REPLICAS="$discoveredCephPoolReplicas"
    fi
    local readyNodeCount
    readyNodeCount=$(kubectl get nodes 2>/dev/null | grep -c ' Ready')
    if [ "$readyNodeCount" -gt "$CEPH_POOL_REPLICAS" ] && [ "$readyNodeCount" -le "3" ]; then
        CEPH_POOL_REPLICAS="$readyNodeCount"
    fi
    set -e
}

function rook_object_store_output() {
    # Rook operator creates this secret from the user CRD just applied
    while ! kubectl -n rook-ceph get secret rook-ceph-object-user-rook-ceph-store-kurl >/dev/null 2>&1 ; do
        sleep 2
    done

    # create the docker-registry bucket through the S3 API
    export OBJECT_STORE_ACCESS_KEY
    OBJECT_STORE_ACCESS_KEY=$(kubectl -n rook-ceph get secret rook-ceph-object-user-rook-ceph-store-kurl -o yaml | grep AccessKey | head -1 | awk '{print $2}' | base64 --decode)
    export OBJECT_STORE_SECRET_KEY
    OBJECT_STORE_SECRET_KEY=$(kubectl -n rook-ceph get secret rook-ceph-object-user-rook-ceph-store-kurl -o yaml | grep SecretKey | head -1 | awk '{print $2}' | base64 --decode)
    export OBJECT_STORE_CLUSTER_IP
    OBJECT_STORE_CLUSTER_IP=$(kubectl -n rook-ceph get service rook-ceph-rgw-rook-ceph-store | tail -n1 | awk '{ print $3}')
    export OBJECT_STORE_CLUSTER_HOST="http://rook-ceph-rgw-rook-ceph-store.rook-ceph"
    # same as OBJECT_STORE_CLUSTER_IP for IPv4, wrapped in brackets for IPv6
    export OBJECT_STORE_CLUSTER_IP_BRACKETED
    OBJECT_STORE_CLUSTER_IP_BRACKETED=$("$DIR"/bin/kurl format-address "$OBJECT_STORE_CLUSTER_IP")
}

# deprecated, use object_store_create_bucket
function rook_create_bucket() {
    local bucket=$1
    local acl="x-amz-acl:private"
    local d
    d=$(LC_TIME="en_US.UTF-8" TZ="UTC" date +"%a, %d %b %Y %T %z")
    local string="PUT\n\n\n${d}\n${acl}\n/${bucket}"
    local sig
    sig=$(echo -en "${string}" | openssl sha1 -hmac "${OBJECT_STORE_SECRET_KEY}" -binary | base64)

    curl -X PUT  \
        --globoff \
        --noproxy "*" \
        -H "Host: $OBJECT_STORE_CLUSTER_IP" \
        -H "Date: $d" \
        -H "$acl" \
        -H "Authorization: AWS $OBJECT_STORE_ACCESS_KEY:$sig" \
        "http://$OBJECT_STORE_CLUSTER_IP_BRACKETED/$bucket" >/dev/null
}

function rook_rgw_is_healthy() {
    curl --globoff --noproxy "*" --fail --silent --insecure "http://${OBJECT_STORE_CLUSTER_IP_BRACKETED}" > /dev/null
}

function rook_version() {
    kubectl -n rook-ceph get deploy rook-ceph-operator -oyaml 2>/dev/null \
        | grep ' image: ' \
        | awk -F':' 'NR==1 { print $3 }' \
        | sed 's/v\([^-]*\).*/\1/'
}

function rook_lvm2() {
    local src="${DIR}/addons/rook/${ROOK_VERSION}"
    if commandExists lvm; then
        return
    fi

    install_host_archives "$src" lvm2
}

function rook_patch_insecure_clients {
    echo "Patching allowance of insecure rook clients"

    # upgrade first before applying auth_allow_insecure_global_id_reclaim policy
    if kubectl -n rook-ceph get configmap rook-config-override -ojsonpath='{.data.config}' | grep -q 'auth_allow_insecure_global_id_reclaim = true' ; then
        local dst="${DIR}/kustomize/rook/operator"
        sed -i 's/auth_allow_insecure_global_id_reclaim = true/auth_allow_insecure_global_id_reclaim = false/' "$dst/configmap-rook-config-override.yaml"
        kubectl -n rook-ceph apply -f "$dst/configmap-rook-config-override.yaml"
    fi

    # Disabling rook global_id reclaim
    kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph config set mon auth_allow_insecure_global_id_reclaim false

    # restart all mons waiting for ok-to-stop
    for mon in $(kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail | grep 'mon\.[a-z][a-z]* has auth_allow_insecure_global_id_reclaim' | grep -o 'mon\.[a-z][a-z]*') ; do
        echo "Awaiting $mon ok-to-stop"
        if ! spinner_until 120 kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph mon ok-to-stop "$mon" >/dev/null 2>&1 ; then
            logWarn "Failed to detect mon $mon ok-to-stop"
        else
            local mon_id mon_pod
            mon_id="$(echo "$mon" | awk -F'.' '{ print $2 }')"
            mon_pod="$(kubectl -n rook-ceph get pods -l ceph_daemon_type=mon -l mon="$mon_id" --no-headers | awk '{ print $1 }')"
            kubectl -n rook-ceph delete pod "$mon_pod"
        fi
    done

    # Checking to ensure ceph status
    if ! spinner_until 120 rook_clients_secure; then
        logWarn "Mon is still allowing insecure clients"
    fi
}

function rook_clients_secure {
    if kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail | grep -q AUTH_INSECURE_GLOBAL_ID_RECLAIM ; then
        return 1
    fi
    return 0
}

# do not downgrade rook or upgrade more than one minor version at a time
function rook_should_skip_rook_install() {
    local current_version="$1"
    local next_version="$2"

    local current_version_minor='' current_version_patch=''
    local next_version_minor='' next_version_patch=''

    semverParse "${current_version}"
    current_version_minor="${minor}"
    current_version_patch="${patch}"

    semverParse "${next_version}"
    next_version_minor="${minor}"
    next_version_patch="${patch}"

    if [ -n "${current_version}" ]; then
        if [ "${current_version_minor}" != "${next_version_minor}" ]; then
            if [ "${current_version_minor}" -gt "${next_version_minor}" ]; then
                echo "Rook ${current_version} is already installed, will not downgrade to ${next_version}"
                return 0
            # only upgrades from prior minor versions supported
            elif [ "${current_version_minor}" -lt "$((next_version_minor-1))" ]; then
                echo "Rook ${current_version} is already installed, will not upgrade to ${next_version}"
                return 0
            fi
        elif [ "${current_version_patch}" -gt "${next_version_patch}" ]; then
            echo "Rook ${current_version} is already installed, will not downgrade to ${next_version}"
            return 0
        fi
    fi
    return 1
}

function rook_maybe_auth_allow_insecure_global_id_reclaim() {
    local dst="${DIR}/kustomize/rook/operator"

    if ! kubectl -n rook-ceph get cephcluster rook-ceph >/dev/null 2>&1 ; then
        # rook ceph not deployed, do not allow since not upgrading
        return
    fi

    local ceph_version
    ceph_version="$(rook_detect_ceph_version)"
    if rook_should_auth_allow_insecure_global_id_reclaim "$ceph_version" ; then
        sed -i 's/auth_allow_insecure_global_id_reclaim = false/auth_allow_insecure_global_id_reclaim = true/' "$dst/configmap-rook-config-override.yaml"
        return
    fi
}

function rook_should_auth_allow_insecure_global_id_reclaim() {
    local ceph_version="$1"

    if [ -z "$ceph_version" ]; then
        # rook ceph not deployed, do not allow since not upgrading
        return 1
    fi

    # https://docs.ceph.com/en/latest/security/CVE-2021-20288/
    semverParse "$ceph_version"
    local ceph_version_major="$major"
    local ceph_version_patch="$patch"

    case "$ceph_version_major" in
    # Pacific v16.2.1 (and later)
    "16")
        if [ "$ceph_version_patch" -lt "1" ]; then
            return 0
        fi
        ;;
    # Octopus v15.2.11 (and later)
    "15")
        if [ "$ceph_version_patch" -lt "11" ]; then
            return 0
        fi
        ;;
    # Nautilus v14.2.20 (and later)
    "14")
        if [ "$ceph_version_patch" -lt "20" ]; then
            return 0
        fi
        ;;
    esac

    return 1
}

function rook_detect_ceph_version() {
    kubectl -n rook-ceph get deployment rook-ceph-mgr-a -o jsonpath='{.metadata.labels.ceph-version}' 2>/dev/null | awk -F'-' '{ print $1 }'
}

# rook_cephfilesystem_patch_singlenode will change the
# requiredDuringSchedulingIgnoredDuringExecution podAntiAffinity rule to the more lenient
# preferredDuringSchedulingIgnoredDuringExecution equivalent. This will allow Rook to continue with
# the upgrade.
function rook_cephfilesystem_patch_singlenode() {
    if ! kubectl -n rook-ceph get cephfilesystem rook-shared-fs -o jsonpath='{.spec.metadataServer.placement.podAntiAffinity}' | grep -q requiredDuringSchedulingIgnoredDuringExecution ; then
        # already patched
        return
    fi

    local src="$DIR/addons/rook/$ROOK_VERSION/cluster"
    rook_cephfilesystem_patch "$src/cephfs/patches/filesystem-singlenode.yaml"
}

function rook_cephfilesystem_patch() {
    local patch="$1"

    local cephfs_generation mds_observedgeneration cephfs_nextgeneration

    cephfs_generation="$(kubectl -n rook-ceph get cephfilesystem rook-shared-fs -o jsonpath='{.metadata.generation}')"
    mds_observedgeneration="$(rook_mds_deployments_observedgeneration)"

    kubectl -n rook-ceph patch cephfilesystem rook-shared-fs --type merge --patch "$(cat "$patch")"

    cephfs_nextgeneration="$(kubectl -n rook-ceph get cephfilesystem rook-shared-fs -o jsonpath='{.metadata.generation}')"
    if [ "$cephfs_generation" = "$cephfs_nextgeneration" ]; then
        # no change
        return
    fi

    echo "Awaiting Rook MDS deployments to roll out"
    if ! spinner_until 1200 rook_mds_deployments_updated "$mds_observedgeneration" ; then
        kubectl -n rook-ceph get deploy -l app=rook-ceph-mds
        bail "Refusing to update cluster rook-ceph, MDS deployments did not roll out"
    fi

    echo "Awaiting Rook MDS deployments up-to-date"
    if ! spinner_until 1200 rook_mds_deployments_uptodate ; then
        kubectl -n rook-ceph get deploy -l app=rook-ceph-mds
        bail "Refusing to update cluster rook-ceph, MDS deployments not up-to-date"
    fi

    # allow the mds daemon to come up
    sleep 60

    echo "Awaiting Rook MDS daemons ok-to-stop"
    if ! spinner_until 1200 rook_mds_daemons_oktostop ; then
        kubectl -n rook-ceph exec deployment/rook-ceph-tools -- ceph mds ok-to-stop a
        kubectl -n rook-ceph exec deployment/rook-ceph-tools -- ceph mds ok-to-stop b
        bail "Refusing to update cluster rook-ceph, MDS daemons not ok-to-stop"
    fi

    echo "Awaiting Ceph healthy"
    if ! $DIR/bin/kurl rook wait-for-health 1200 ; then
        kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
        bail "Refusing to update cluster rook-ceph, Ceph is not healthy"
    fi
}

function rook_mds_deployments_uptodate() {
    local replicas ready_replicas updated_replicas
    replicas="$(kubectl -n rook-ceph get deploy -l app=rook-ceph-mds -o jsonpath='{.items[*].status.replicas}')"
    ready_replicas="$(kubectl -n rook-ceph get deploy -l app=rook-ceph-mds -o jsonpath='{.items[*].status.readyReplicas}')"
    updated_replicas="$(kubectl -n rook-ceph get deploy -l app=rook-ceph-mds -o jsonpath='{.items[*].status.updatedReplicas}')"
    [ -n "$replicas" ] && [ "$replicas" = "$ready_replicas" ] && [ "$replicas" = "$updated_replicas" ]
}

function rook_mds_deployments_updated() {
    local previous="$1"
    for line in $previous; do
        if rook_mds_deployments_observedgeneration | grep -q "$line" ; then
            return 1
        fi
    done
    return 0
}

function rook_mds_deployments_observedgeneration() {
    kubectl -n rook-ceph get deploy -l app=rook-ceph-mds -o jsonpath='{range .items[*]}{.metadata.name}={.status.observedGeneration}{"\n"}{end}'
}

function rook_mds_daemons_oktostop() {
    local ids=
    ids="$(kubectl -n rook-ceph get deploy -l app=rook-ceph-mds -oname | sed 's/.*-rook-shared-fs-\(.*\)/\1/')"
    for id in $ids; do
        if ! kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph mds ok-to-stop "$id" >/dev/null 2>&1 ; then
            return 1
        fi
    done
    return 0
}

function rook_ceph_cluster_ready_spinner() {
    log "Awaiting CephCluster CR to report Ready"
    local delay="$1"
    local duration="$2"
    local ready_threshold=5
    local successful_ready_status_count=0
    local spinstr='|/-\'
    local start_time=
    local end_time=

    # defaults
    if [ -z "$delay" ]; then
        delay=5
    fi
    if [ -z "$duration" ]; then
        duration=300
    fi

    start_time=$(date +%s)
    end_time=$((start_time+duration))
    while [ "$(date +%s)" -lt $end_time ]
    do
        local temp=${spinstr#?}
        local spinstr=$temp${spinstr%"$temp"}
        local ceph_status_phase=
        local ceph_status_msg=
        ceph_status_phase=$(kubectl -n rook-ceph get cephcluster rook-ceph -o jsonpath='{.status.phase}')
        ceph_status_msg=$(kubectl -n rook-ceph get cephcluster rook-ceph -o jsonpath='{.status.message}')
        if [[ "$ceph_status_phase" == "Ready" ]]; then
            log "  Current CephCluster status is: $ceph_status_phase"
            successful_ready_status_count=$((successful_ready_status_count+1))
            if [ $successful_ready_status_count -eq $ready_threshold ]; then
                log "CephCluster is ready"
                return 0
            fi
        else
            log "  Current CephCluster status is $ceph_status_phase: $ceph_status_msg"
            successful_ready_status_count=0
        fi

        # simulate a spinner
        printf " [%c]  " "$spinstr"
        printf "\b\b\b\b\b\b"
        sleep "$delay"
    done
    logWarn "Rook CephCluster is not ready"
}


# wait for Rook deployment pods to be running/completed
function rook_maybe_wait_for_rollout() {
    # wait for Rook CephCluster CR to report Ready
    # probe set to 10s
    # timeout set to 300s (5mins)
    rook_ceph_cluster_ready_spinner 10 300

    log "Awaiting Rook pods to transition to Running"
    if ! spinner_until 120 check_for_running_pods "rook-ceph"; then
        logWarn "Rook-ceph rollout did not complete within the allotted time"
    fi
}
