# shellcheck disable=SC2148

function rookupgrade_10to14_upgrade() {
    local from_version="$1"

    local upgrade_files_path="$DIR/addons/rookupgrade/10to14"

    # if it is less than or equal we re-apply in cause of a failure mid upgrade
    if [ "$(rook_upgrade_compare_rook_versions "$from_version" "1.1")" != "1" ]; then
        "$DIR"/bin/kurl rook hostpath-to-block
        "$DIR"/bin/kurl rook wait-for-health

        echo "Rescaling pgs per pool"
        # enabling autoscaling at this point doesn't scale down the number of PGs sufficiently in my testing - it will be enabled after installing 1.4.9
        local osd_pools=
        local non_osd_pools=
        osd_pools="$(kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd pool ls | grep rook-ceph-store)"
        non_osd_pools="$(kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd pool ls | grep -v rook-ceph-store)"
        rookupgrade_10to14_scale_down_osd_pool_pg_num "$osd_pools" 16
        rookupgrade_10to14_scale_down_osd_pool_pg_num "$non_osd_pools" 32
        # log "Waiting for pool pgs to scale down"
        # rookupgrade_10to14_osd_pool_wait_for_pg_num "$osd_pools" 16
        # rookupgrade_10to14_osd_pool_wait_for_pg_num "$non_osd_pools" 32

        logStep "Upgrading to Rook 1.1.9"
        "$DIR"/bin/kurl rook wait-for-health

        # first update rbac and other resources for 1.1
        kubectl create --save-config -f "$upgrade_files_path/upgrade-from-v1.0-create.yaml" || true # resources may already be present
        kubectl apply -f "$upgrade_files_path/upgrade-from-v1.0-apply.yaml"

        # change the default osd pool size from 3 to 1
        kubectl apply -f "$upgrade_files_path/rook-config-override.yaml"

        kubectl delete crd --ignore-not-found volumesnapshotclasses.snapshot.storage.k8s.io volumesnapshotcontents.snapshot.storage.k8s.io volumesnapshots.snapshot.storage.k8s.io
        kubectl -n rook-ceph set image deploy/rook-ceph-operator rook-ceph-operator=rook/ceph:v1.1.9
        kubectl -n rook-ceph set image deploy/rook-ceph-tools rook-ceph-tools=rook/ceph:v1.1.9
        echo "Waiting for Rook 1.1.9 to rollout throughout the cluster, this may take some time"
        "$DIR"/bin/kurl rook wait-for-rook-version "v1.1.9"
        # todo make sure that the RGW isn't getting stuck
        echo "Rook 1.1.9 has been rolled out throughout the cluster"

        echo "Upgrading CRDs to Rook 1.1"
        kubectl apply -f "$upgrade_files_path/upgrade-from-v1.0-crds.yaml"

        semverCompare "$(current_ceph_version)" "14.2.5"
        if [ "$SEMVER_COMPARE_RESULT" != "1" ]; then
            echo "Upgrading to Ceph 14.2.5"

            kubectl -n rook-ceph patch CephCluster rook-ceph --type=merge -p '{"spec": {"cephVersion": {"image": "ceph/ceph:v14.2.5-20191210"}}}'
            kubectl patch deployment -n rook-ceph csi-rbdplugin-provisioner -p '{"spec": {"template": {"spec":{"containers":[{"name":"csi-snapshotter","imagePullPolicy":"IfNotPresent"}]}}}}'
            "$DIR"/bin/kurl rook wait-for-ceph-version "14.2.5"

            "$DIR"/bin/kurl rook wait-for-health

            echo "Upgraded to Ceph 14.2.5 successfully"
        fi

        logSuccess "Upgraded to Rook 1.1.9 successfully"
    fi

    if [ "$(rook_upgrade_compare_rook_versions "$from_version" "1.2")" != "1" ]; then
        logStep "Upgrading to Rook 1.2.7"
        "$DIR"/bin/kurl rook wait-for-health

        echo "Updating resources for Rook 1.2.7"
        # apply RBAC not contained in the git repo for some reason
        kubectl apply -f "$upgrade_files_path/rook-ceph-osd-rbac.yaml"
        kubectl apply -f "$upgrade_files_path/upgrade-from-v1.1-apply.yaml"

        kubectl -n rook-ceph set image deploy/rook-ceph-operator rook-ceph-operator=rook/ceph:v1.2.7
        kubectl -n rook-ceph set image deploy/rook-ceph-tools rook-ceph-tools=rook/ceph:v1.2.7
        echo "Waiting for Rook 1.2.7 to rollout throughout the cluster, this may take some time"
        "$DIR"/bin/kurl rook wait-for-rook-version "v1.2.7"
        echo "Rook 1.2.7 has been rolled out throughout the cluster"
        "$DIR"/bin/kurl rook wait-for-health

        echo "Upgrading CRDs to Rook 1.2"
        kubectl apply -f "$upgrade_files_path/upgrade-from-v1.1-crds.yaml"

        "$DIR"/bin/kurl rook wait-for-health

        logSuccess "Upgraded to Rook 1.2.7 successfully"
    fi

    if [ "$(rook_upgrade_compare_rook_versions "$from_version" "1.3")" != "1" ]; then
        logStep "Upgrading to Rook 1.3.11"
        "$DIR"/bin/kurl rook wait-for-health

        echo "Updating resources for Rook 1.3.11"
        kubectl apply -f "$upgrade_files_path/upgrade-from-v1.2-apply.yaml"
        kubectl apply -f "$upgrade_files_path/upgrade-from-v1.2-crds.yaml"
        kubectl -n rook-ceph set image deploy/rook-ceph-operator rook-ceph-operator=rook/ceph:v1.3.11
        kubectl -n rook-ceph set image deploy/rook-ceph-tools rook-ceph-tools=rook/ceph:v1.3.11

        echo "Waiting for Rook 1.3.11 to rollout throughout the cluster, this may take some time"
        "$DIR"/bin/kurl rook wait-for-rook-version "v1.3.11"
        echo "Rook 1.3.11 has been rolled out throughout the cluster"
        "$DIR"/bin/kurl rook wait-for-health

        logSuccess "Upgraded to Rook 1.3.11 successfully"
    fi

    if [ "$(rook_upgrade_compare_rook_versions "$from_version" "1.4")" != "1" ]; then
        logStep "Upgrading to Rook 1.4.9"
        "$DIR"/bin/kurl rook wait-for-health

        echo "Updating resources for Rook 1.4.9"
        kubectl delete -f "$upgrade_files_path/upgrade-from-v1.3-delete.yaml"
        kubectl apply -f "$upgrade_files_path/upgrade-from-v1.3-apply.yaml"
        kubectl apply -f "$upgrade_files_path/upgrade-from-v1.3-crds.yaml"
        kubectl -n rook-ceph set image deploy/rook-ceph-operator rook-ceph-operator=rook/ceph:v1.4.9
        kubectl apply -f "$upgrade_files_path/rook-ceph-tools-14.yaml"

        echo "Waiting for Rook 1.4.9 to rollout throughout the cluster, this may take some time"
        "$DIR"/bin/kurl rook wait-for-rook-version "v1.4.9"
        echo "Rook 1.4.9 has been rolled out throughout the cluster"
        "$DIR"/bin/kurl rook wait-for-health

        semverCompare "$(current_ceph_version)" "15.2.8"
        if [ "$SEMVER_COMPARE_RESULT" != "1" ]; then
            echo "Upgrading to Ceph 15.2.8"
            kubectl -n rook-ceph patch CephCluster rook-ceph --type=merge -p '{"spec": {"cephVersion": {"image": "ceph/ceph:v15.2.8-20201217"}}}'
            "$DIR"/bin/kurl rook wait-for-ceph-version "15.2.8-0"

            echo "Enabling pg pool autoscaling"
            kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd pool ls | \
            xargs -I {} kubectl -n rook-ceph exec deploy/rook-ceph-tools -- \
            ceph osd pool set {} pg_autoscale_mode on
            echo "Current pg pool autoscaling status:"
            kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd pool autoscale-status

            "$DIR"/bin/kurl rook wait-for-health

            echo "Upgraded to Ceph 15.2.8 successfully"
        fi

        logSuccess "Upgraded to Rook 1.4.9 successfully"
    fi
}

# rookupgrade_10to14_scale_down_osd_pool_pg_num will scale a list of pools down to a given pg_num
function rookupgrade_10to14_scale_down_osd_pool_pg_num() {
    local pool_names="$1"
    local pg_num_scale="$2"
    for pool_name in $pool_names; do
        local pg_num=
        pg_num="$(kubectl -n rook-ceph exec deploy/rook-ceph-tools -- \
            ceph osd pool get "$pool_name" pg_num | awk '{print $2}')"
        if [ -n "$pg_num" ] && [ "$pg_num_scale" -gt "$pg_num"  ]; then
            log "Refusing to increase pg_num for pool $pool_name (from $pg_num to $pg_num_scale)"
            continue
        fi
        kubectl -n rook-ceph exec deploy/rook-ceph-tools -- \
            ceph osd pool set "$pool_name" pg_num "$pg_num_scale"
    done
}

# rookupgrade_10to14_osd_pool_wait_for_pg_num waits for a list of pools to have a pg_num less than
# or equal to the given scale
function rookupgrade_10to14_osd_pool_wait_for_pg_num() {
    local pool_names="$1"
    local pg_num_scale="$2"
    for pool_name in $pool_names ; do
        # this takes a really long time
        spinner_until 1200 rookupgrade_10to14_osd_pool_pg_num_lte "$pool_name" "$pg_num_scale"
    done
}

# rookupgrade_10to14_osd_pool_pg_num_lte returns true if the pg_num for a pool is less than or
# equal to the given value
function rookupgrade_10to14_osd_pool_pg_num_lte() {
    local pool_name="$1"
    local pg_num_scale="$2"
    local pg_num=
    pg_num="$(kubectl -n rook-ceph exec deploy/rook-ceph-tools -- \
        ceph osd pool get "$pool_name" pg_num | awk '{print $2}')"
    [ -n "$pg_num" ] && [ "$pg_num" -le "$pg_num_scale" ]
}
