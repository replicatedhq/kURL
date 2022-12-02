# shellcheck disable=SC2148

function rookupgrade_10to14_upgrade() {
    local from_version="$1"

    local upgrade_files_path="$DIR/addons/rookupgrade/10to14"

    # if it is less than or equal we re-apply in cause of a failure mid upgrade
    if [ "$(rook_upgrade_compare_rook_versions "$from_version" "1.1")" != "1" ]; then
        "$DIR"/bin/kurl rook hostpath-to-block

        echo "Rescaling pgs per pool"
        # enabling autoscaling at this point doesn't scale down the number of PGs sufficiently in my testing - it will be enabled after installing 1.4.9
        kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd pool ls | \
            grep rook-ceph-store | \
            xargs -I {} kubectl -n rook-ceph exec deploy/rook-ceph-tools -- \
            ceph osd pool set {} pg_num 16
        kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd pool ls | \
            grep -v rook-ceph-store | \
            xargs -I {} kubectl -n rook-ceph exec deploy/rook-ceph-tools -- \
            ceph osd pool set {} pg_num 32
        "$DIR"/bin/kurl rook wait-for-health

        logStep "Upgrading to Rook 1.1.9"

        # first update rbac and other resources for 1.1
        kubectl create --save-config -f "$upgrade_files_path/upgrade-from-v1.0-create.yaml" || true # resources may already be present
        kubectl apply -f "$upgrade_files_path/upgrade-from-v1.0-apply.yaml"

        # change the default osd pool size from 3 to 1
        kubectl apply -f "$upgrade_files_path/rook-config-override.yaml"

        kubectl delete crd volumesnapshotclasses.snapshot.storage.k8s.io volumesnapshotcontents.snapshot.storage.k8s.io volumesnapshots.snapshot.storage.k8s.io || true # resources may not be present
        kubectl -n rook-ceph set image deploy/rook-ceph-operator rook-ceph-operator=rook/ceph:v1.1.9
        kubectl -n rook-ceph set image deploy/rook-ceph-tools rook-ceph-tools=rook/ceph:v1.1.9
        echo "Waiting for Rook 1.1.9 to rollout throughout the cluster, this may take some time"
        "$DIR"/bin/kurl rook wait-for-rook-version "v1.1.9"
        # todo make sure that the RGW isn't getting stuck
        echo "Rook 1.1.9 has been rolled out throughout the cluster"

        echo "Upgrading CRDs to Rook 1.1"
        kubectl apply -f "$upgrade_files_path/upgrade-from-v1.0-crds.yaml"

        echo "Upgrading to Ceph 14.2.5"

        kubectl -n rook-ceph patch CephCluster rook-ceph --type=merge -p '{"spec": {"cephVersion": {"image": "ceph/ceph:v14.2.5-20191210"}}}'
        kubectl patch deployment -n rook-ceph csi-rbdplugin-provisioner -p '{"spec": {"template": {"spec":{"containers":[{"name":"csi-snapshotter","imagePullPolicy":"IfNotPresent"}]}}}}'
        "$DIR"/bin/kurl rook wait-for-ceph-version "14.2.5"

        "$DIR"/bin/kurl rook wait-for-health

        echo "Upgraded to Ceph 14.2.5 successfully"

        logSuccess "Upgraded to Rook 1.1.9 successfully"
    fi

    if [ "$(rook_upgrade_compare_rook_versions "$from_version" "1.2")" != "1" ]; then
        logStep "Upgrading to Rook 1.2.7"

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

        logSuccess "Upgraded to Rook 1.4.9 successfully"
    fi
}
