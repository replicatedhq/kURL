# shellcheck disable=SC2148

function rookupgrade_10to14_upgrade() {
    local from_version="$1"
    local upgrade_files_path="$DIR/addons/rookupgrade/10to14"

    # if it is less than or equal we re-apply in cause of a failure mid upgrade
    if [ "$(common_upgrade_compare_versions "$from_version" "1.1")" != "1" ]; then

        log "Awaiting up to 5 minutes to check Rook Ceph Pod(s) are Running"
        if ! spinner_until 300 check_for_running_pods "rook-ceph"; then
            logWarn "Rook Ceph has unhealthy Pod(s)"
        fi

        # this will start the rook toolbox if it doesn't already exist
        log "Waiting for rook to be healthy"
        if ! "$DIR"/bin/kurl rook wait-for-health 300 ; then
            kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
            bail "Failed to verify the updated cluster, Ceph is not healthy"
        fi

        # If the rook version installed is 1.0.4-14.2.21 then, we need to workaround
        # the issue scenario: https://github.com/rook/rook/issues/11496
        semverCompare "$(current_ceph_version)" "14.2.21"
        if [ "$SEMVER_COMPARE_RESULT" != "-1" ]; then # greater than or equal to 14.2.21
            log "Setting mon auth_allow_insecure_global_id_reclaim true"
            kubectl -n rook-ceph exec deploy/rook-ceph-operator -- ceph config set mon auth_allow_insecure_global_id_reclaim true
        fi

        log "Updating the Ceph mon count"
        # If mon count is less than actual count, update mon count to actual count. Otherwise
        # updating to the latest CRDs may reduce the mon count, as preferredCount has been removed
        # from the CRD in Rook 1.1.
        # https://github.com/rook/rook/commit/e2fccdf03b4887a90892ef6c493a3f25cbbd23dd
        local mon_count=
        local mon_preferred_count=
        mon_count="$(kubectl -n rook-ceph get cephcluster rook-ceph -o jsonpath='{.spec.mon.count}')"
        if [ -z "$mon_count" ]; then
            mon_count=1
        fi
        mon_preferred_count="$(kubectl -n rook-ceph get cephcluster rook-ceph -o jsonpath='{.spec.mon.preferredCount}')"
        if [ -n "$mon_preferred_count" ] && [ "$mon_count" -lt "$mon_preferred_count" ]; then
            local actual_mon_count=
            actual_mon_count="$(kubectl -n rook-ceph exec deploy/rook-ceph-operator -- ceph mon stat | grep -o '[0-9]* mons* at' | awk '{ print $1 }')"
            if [ -n "$actual_mon_count" ] && [ "$mon_count" -lt "$actual_mon_count" ]; then
                log "Updating mon count to match actual mon count $actual_mon_count"
                kubectl -n rook-ceph patch cephcluster rook-ceph --type merge -p '{"spec":{"mon":{"count":'"$actual_mon_count"'}}}'
                if ! "$DIR"/bin/kurl rook wait-for-health 300 ; then
                    kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
                    bail "Failed to verify the updated cluster, Ceph is not healthy"
                fi
            fi
        fi

        log "Preparing migration"

        log "Waiting for Rook to be healthy"
        if ! "$DIR"/bin/kurl rook wait-for-health 300 ; then
            kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
            bail "Failed to verify the updated cluster, Ceph is not healthy"
        fi

        log "Rescaling pgs per pool"

        # enabling autoscaling at this point doesn't scale down the number of PGs sufficiently in my testing - it will be enabled after installing 1.4.9
        local osd_pools=
        local non_osd_pools=
        osd_pools="$(kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd pool ls | grep rook-ceph-store)"
        non_osd_pools="$(kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd pool ls | grep -v rook-ceph-store)"
        rookupgrade_10to14_scale_down_osd_pool_pg_num "$osd_pools" 16
        rookupgrade_10to14_scale_down_osd_pool_pg_num "$non_osd_pools" 32

        log "Waiting for pool pgs to scale down"
        rookupgrade_10to14_osd_pool_wait_for_pg_num "$osd_pools" 16
        rookupgrade_10to14_osd_pool_wait_for_pg_num "$non_osd_pools" 32
        if ! "$DIR"/bin/kurl rook wait-for-health 300 ; then
            kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
            bail "Failed to verify the updated cluster, Ceph is not healthy"
        fi

        "$DIR"/bin/kurl rook hostpath-to-block

        logStep "Upgrading to Rook 1.1.9"
        if ! "$DIR"/bin/kurl rook wait-for-health 300 ; then
            kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
            bail "Failed to verify the updated cluster, Ceph is not healthy"
        fi

        # first update rbac and other resources for 1.1
        kubectl create --save-config -f "$upgrade_files_path/upgrade-from-v1.0-create.yaml" || true # resources may already be present
        kubectl apply -f "$upgrade_files_path/upgrade-from-v1.0-apply.yaml"

        # change the default osd pool size from 3 to 1
        kubectl apply -f "$upgrade_files_path/rook-config-override.yaml"

        kubectl delete crd --ignore-not-found volumesnapshotclasses.snapshot.storage.k8s.io volumesnapshotcontents.snapshot.storage.k8s.io volumesnapshots.snapshot.storage.k8s.io
        kubectl -n rook-ceph set image deploy/rook-ceph-operator rook-ceph-operator=rook/ceph:v1.1.9
        kubectl -n rook-ceph set image deploy/rook-ceph-tools rook-ceph-tools=rook/ceph:v1.1.9

        log "Awaiting up to 5 minutes to check Rook Ceph Pod(s) are Running"
        if ! spinner_until 300 check_for_running_pods "rook-ceph"; then
            logWarn "Rook Ceph has unhealthy Pod(s)"
        fi

        log "Waiting for Rook 1.1.9 to rollout throughout the cluster, this may take some time"
        if ! "$DIR"/bin/kurl rook wait-for-rook-version "v1.1.9" --timeout=1200 ; then
            logWarn "Timeout waiting for Rook version 1.1.9 rolled out"
            logStep "Checking Rook versions and replicas"
            kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{.metadata.name}{"  \treq/upd/avl: "}{.spec.replicas}{"/"}{.status.updatedReplicas}{"/"}{.status.readyReplicas}{"  \trook-version="}{.metadata.labels.rook-version}{"\n"}{end}'
            local rook_versions=
            rook_versions="$(kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"rook-version="}{.metadata.labels.rook-version}{"\n"}{end}' | sort | uniq)"
            if [ -n "${rook_versions}" ] && [ "$(echo "${rook_versions}" | wc -l)" -gt "1" ]; then
                logWarn "Detected multiple Rook versions"
                logWarn "${rook_versions}"
                logWarn "Failed to verify the Rook upgrade, multiple Rook versions detected"
            fi
            bail "Failed to verify the Rook upgrade"
        fi

        log "Rook 1.1.9 has been rolled out throughout the cluster"
        if ! "$DIR"/bin/kurl rook wait-for-health 300 ; then
            kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
            bail "Failed to verify the updated cluster, Ceph is not healthy"
        fi

        log "Upgrading CRDs to Rook 1.1"
        kubectl apply -f "$upgrade_files_path/upgrade-from-v1.0-crds.yaml"

        semverCompare "$(current_ceph_version)" "14.2.5"
        if [ "$SEMVER_COMPARE_RESULT" != "1" ]; then
            log "Upgrading to Ceph 14.2.5"

            kubectl -n rook-ceph patch CephCluster rook-ceph --type=merge -p '{"spec": {"cephVersion": {"image": "ceph/ceph:v14.2.5-20201116"}}}'
            kubectl patch deployment -n rook-ceph csi-rbdplugin-provisioner -p '{"spec": {"template": {"spec":{"containers":[{"name":"csi-snapshotter","imagePullPolicy":"IfNotPresent"}]}}}}'

            log "Awaiting up to 5 minutes to check Rook Ceph Pod(s) are Running"
            if ! spinner_until 300 check_for_running_pods "rook-ceph"; then
                logWarn "Rook Ceph has unhealthy Pod(s)"
            fi

            if ! "$DIR"/bin/kurl rook wait-for-ceph-version "14.2.5" --timeout=1200 ; then
                logWarn "Timeout waiting for Ceph version to be rolled out"
                log "Checking Ceph versions and replicas"
                kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{.metadata.name}{"  \treq/upd/avl: "}{.spec.replicas}{"/"}{.status.updatedReplicas}{"/"}{.status.readyReplicas}{"  \tceph-version="}{.metadata.labels.ceph-version}{"\n"}{end}'
                local ceph_versions_found=
                ceph_versions_found="$(kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"ceph-version="}{.metadata.labels.ceph-version}{"\n"}{end}' | sort | uniq)"
                # Fail when more than one version is found
                if [ -n "${ceph_versions_found}" ] && [ "$(echo "${ceph_versions_found}" | wc -l)" -gt "1" ]; then
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

            if ! "$DIR"/bin/kurl rook wait-for-health 300 ; then
                kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
                bail "Failed to verify the updated cluster, Ceph is not healthy"
            fi

            logSuccess "Upgraded to Ceph 14.2.5 successfully"
        fi

        logSuccess "Upgraded to Rook 1.1.9 successfully"
    fi

    if [ "$(common_upgrade_compare_versions "$from_version" "1.2")" != "1" ]; then
        logStep "Upgrading to Rook 1.2.7"
        if ! "$DIR"/bin/kurl rook wait-for-health 300 ; then
            kubectl -n rook-ceph exec deploy/rook-ceph-tools --ceph status
            bail "Failed to verify the updated cluster, Ceph is not healthy"
        fi

        log "Updating resources for Rook 1.2.7"
        # apply RBAC not contained in the git repo for some reason
        kubectl apply -f "$upgrade_files_path/rook-ceph-osd-rbac.yaml"
        kubectl apply -f "$upgrade_files_path/upgrade-from-v1.1-apply.yaml"

        kubectl -n rook-ceph set image deploy/rook-ceph-operator rook-ceph-operator=rook/ceph:v1.2.7
        kubectl -n rook-ceph set image deploy/rook-ceph-tools rook-ceph-tools=rook/ceph:v1.2.7

        log "Awaiting up to 5 minutes to check Rook Ceph Pod(s) are Running"
        if ! spinner_until 300 check_for_running_pods "rook-ceph"; then
            logWarn "Rook Ceph has unhealthy Pod(s)"
        fi

        log "Waiting for Rook 1.2.7 to rollout throughout the cluster, this may take some time"
        if ! "$DIR"/bin/kurl rook wait-for-rook-version "v1.2.7" --timeout=1200 ; then
            logWarn "Timeout waiting for Rook version 1.2.7 rolled out"
            logStep "Checking Rook versions and replicas"
            kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{.metadata.name}{"  \treq/upd/avl: "}{.spec.replicas}{"/"}{.status.updatedReplicas}{"/"}{.status.readyReplicas}{"  \trook-version="}{.metadata.labels.rook-version}{"\n"}{end}'
            local rook_versions=
            rook_versions="$(kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"rook-version="}{.metadata.labels.rook-version}{"\n"}{end}' | sort | uniq)"
            if [ -n "${rook_versions}" ] && [ "$(echo "${rook_versions}" | wc -l)" -gt "1" ]; then
                logWarn "Detected multiple Rook versions"
                logWarn "${rook_versions}"
                logWarn "Failed to verify the Rook upgrade, multiple Rook versions detected"
            fi
            bail "Failed to verify the Rook upgrade"
        fi

        log "Rook 1.2.7 has been rolled out throughout the cluster"
        if ! "$DIR"/bin/kurl rook wait-for-health 300 ; then
            kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
            bail "Failed to verify the updated cluster, Ceph is not healthy"
        fi

        log "Upgrading CRDs to Rook 1.2"
        kubectl apply -f "$upgrade_files_path/upgrade-from-v1.1-crds.yaml"

        if ! "$DIR"/bin/kurl rook wait-for-health 300 ; then
            kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
            bail "Failed to verify the updated cluster, Ceph is not healthy"
        fi

        logSuccess "Upgraded to Rook 1.2.7 successfully"
    fi

    if [ "$(common_upgrade_compare_versions "$from_version" "1.3")" != "1" ]; then
        logStep "Upgrading to Rook 1.3.11"
        if ! "$DIR"/bin/kurl rook wait-for-health 300 ; then
            kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
            bail "Failed to verify the updated cluster, Ceph is not healthy"
        fi

        log "Updating resources for Rook 1.3.11"
        kubectl apply -f "$upgrade_files_path/upgrade-from-v1.2-apply.yaml"
        kubectl apply -f "$upgrade_files_path/upgrade-from-v1.2-crds.yaml"
        kubectl -n rook-ceph set image deploy/rook-ceph-operator rook-ceph-operator=rook/ceph:v1.3.11
        kubectl -n rook-ceph set image deploy/rook-ceph-tools rook-ceph-tools=rook/ceph:v1.3.11

        log "Awaiting up to 5 minutes to check Rook Ceph Pod(s) are Running"
        if ! spinner_until 300 check_for_running_pods "rook-ceph"; then
            logWarn "Rook Ceph has unhealthy Pod(s)"
        fi

        log "Waiting for Rook 1.3.11 to rollout throughout the cluster, this may take some time"
        if ! "$DIR"/bin/kurl rook wait-for-rook-version "v1.3.11" --timeout=1200 ; then
            logWarn "Timeout waiting for Rook version 1.3.11 rolled out"
            logStep "Checking Rook versions and replicas"
            kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{.metadata.name}{"  \treq/upd/avl: "}{.spec.replicas}{"/"}{.status.updatedReplicas}{"/"}{.status.readyReplicas}{"  \trook-version="}{.metadata.labels.rook-version}{"\n"}{end}'
            local rook_versions=
            rook_versions="$(kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"rook-version="}{.metadata.labels.rook-version}{"\n"}{end}' | sort | uniq)"
            if [ -n "${rook_versions}" ] && [ "$(echo "${rook_versions}" | wc -l)" -gt "1" ]; then
                logWarn "Detected multiple Rook versions"
                logWarn "${rook_versions}"
                logWarn "Failed to verify the Rook upgrade, multiple Rook versions detected"
            fi
            bail "Failed to verify the Rook upgrade"
        fi

        log "Rook 1.3.11 has been rolled out throughout the cluster"
        if ! "$DIR"/bin/kurl rook wait-for-health 300 ; then
            kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
            bail "Failed to verify the updated cluster, Ceph is not healthy"
        fi

        logSuccess "Upgraded to Rook 1.3.11 successfully"
    fi

    if [ "$(common_upgrade_compare_versions "$from_version" "1.4")" != "1" ]; then
        logStep "Upgrading to Rook 1.4.9"
        if ! "$DIR"/bin/kurl rook wait-for-health 300 ; then
            kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
            bail "Failed to verify the updated cluster, Ceph is not healthy"
        fi

        log "Updating resources for Rook 1.4.9"
        kubectl delete -f "$upgrade_files_path/upgrade-from-v1.3-delete.yaml"
        kubectl apply -f "$upgrade_files_path/upgrade-from-v1.3-apply.yaml"
        kubectl apply -f "$upgrade_files_path/upgrade-from-v1.3-crds.yaml"
        kubectl -n rook-ceph set image deploy/rook-ceph-operator rook-ceph-operator=rook/ceph:v1.4.9
        kubectl apply -f "$upgrade_files_path/rook-ceph-tools-14.yaml"

        log "Awaiting up to 5 minutes to check Rook Ceph Pod(s) are Running"
        if ! spinner_until 300 check_for_running_pods "rook-ceph"; then
            logWarn "Rook Ceph has unhealthy Pod(s)"
        fi

        log "Waiting for Rook 1.4.9 to rollout throughout the cluster, this may take some time"
        if ! "$DIR"/bin/kurl rook wait-for-rook-version "v1.4.9" --timeout=1200 ; then
            logWarn "Timeout waiting for Rook version 1.4.9 rolled out"
            logStep "Checking Rook versions and replicas"
            kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{.metadata.name}{"  \treq/upd/avl: "}{.spec.replicas}{"/"}{.status.updatedReplicas}{"/"}{.status.readyReplicas}{"  \trook-version="}{.metadata.labels.rook-version}{"\n"}{end}'
            local rook_versions=
            rook_versions="$(kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"rook-version="}{.metadata.labels.rook-version}{"\n"}{end}' | sort | uniq)"
            if [ -n "${rook_versions}" ] && [ "$(echo "${rook_versions}" | wc -l)" -gt "1" ]; then
                logWarn "Detected multiple Rook versions"
                logWarn "${rook_versions}"
                logWarn "Failed to verify the Rook upgrade, multiple Rook versions detected"
            fi
            bail "Failed to verify the Rook upgrade"

        fi

        log "Rook 1.4.9 has been rolled out throughout the cluster"
        if ! "$DIR"/bin/kurl rook wait-for-health 300 ; then
            kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
            bail "Failed to verify the updated cluster, Ceph is not healthy"
        fi

        semverCompare "$(current_ceph_version)" "15.2.8"
        if [ "$SEMVER_COMPARE_RESULT" != "1" ]; then
            logStep "Upgrading to Ceph 15.2.8"
            kubectl -n rook-ceph patch CephCluster rook-ceph --type=merge -p '{"spec": {"cephVersion": {"image": "ceph/ceph:v15.2.8-20201217"}}}'

            # EKCO will scale device_health_metrics to 3 once the cluster is upgraded to Ceph
            # 15.2.8, but since we have scaled EKCO to 0 replicas it cannot, so we need to do it
            # manually.
            log "Waiting for device_health_metrics pool to be created"
            if ! rookupgrade_10to14_wait_for_pool_device_health_metrics ; then
                bail "Timed out waiting for device_health_metrics pool to be created"
            fi
            rookupgrade_10to14_maybe_scale_pool_device_health_metrics

            log "Awaiting up to 5 minutes to check Rook Ceph Pod(s) are Running"
            if ! spinner_until 300 check_for_running_pods "rook-ceph"; then
                logWarn "Rook Ceph has unhealthy Pod(s)"
            fi

            if ! "$DIR"/bin/kurl rook wait-for-ceph-version "15.2.8-0" --timeout=1200 ; then
                logWarn "Timeout waiting for Ceph version 15.2.8-0 rolled out"
                log "Checking Ceph versions and replicas"
                kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{.metadata.name}{"  \treq/upd/avl: "}{.spec.replicas}{"/"}{.status.updatedReplicas}{"/"}{.status.readyReplicas}{"  \tceph-version="}{.metadata.labels.ceph-version}{"\n"}{end}'
                local ceph_versions_found=
                ceph_versions_found="$(kubectl -n rook-ceph get deployment -l rook_cluster=rook-ceph -o jsonpath='{range .items[*]}{"ceph-version="}{.metadata.labels.ceph-version}{"\n"}{end}' | sort | uniq)"
                if [ -n "${ceph_versions_found}" ] && [ "$(echo "${ceph_versions_found}" | wc -l)" -gt "1" ]; then
                    if [ "$(echo "${ceph_versions_found}" | wc -l)" == "2" ] && [ "$(echo "${ceph_versions_found}" | grep "0.0.0-0")" ]; then
                        log "Found two ceph versions but one of them is 0.0.0-0 which will be ignored"
                        echo "${ceph_versions_found}"
                    else
                        logWarn "Detected multiple Ceph versions"
                        logWarn "${ceph_versions_found}"
                        logWarn "Failed to verify the Ceph upgrade, multiple Ceph versions detected"
                    fi
                fi

                if [[ "$(echo "${ceph_versions_found}")" == *"15.2.8"* ]]; then
                    logWarn "Ceph version found ${ceph_versions_found}. New Ceph version ${ceph_version} failed to deploy"
                fi
                bail "New Ceph version failed to deploy"
            fi

            log "Enabling pg pool autoscaling"
            kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd pool ls | \
            xargs -I {} kubectl -n rook-ceph exec deploy/rook-ceph-tools -- \
            ceph osd pool set {} pg_autoscale_mode on

            log "Current pg pool autoscaling status:"
            kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd pool autoscale-status

            if ! "$DIR"/bin/kurl rook wait-for-health 300 ; then
                kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
                bail "Failed to verify the updated cluster, Ceph is not healthy"
            fi

            logSuccess "Upgraded to Ceph 15.2.8 successfully"
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

# rookupgrade_10to14_wait_for_pool_device_health_metrics will wait for the device_health_metrics
# pool to be created when upgrading to Ceph 15.2.8
function rookupgrade_10to14_wait_for_pool_device_health_metrics() {
    spinner_until 1200 rookupgrade_10to14_pool_device_health_metrics_exists
}

# rookupgrade_10to14_pool_device_health_metrics_exists will return 0 if the device_health_metrics
# pool exists
function rookupgrade_10to14_pool_device_health_metrics_exists() {
    kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd pool ls | grep -q device_health_metrics
}

# rookupgrade_10to14_maybe_scale_pool_device_health_metrics will scale the device_health_metrics
# pool to the same replication of the replicapool, assuming EKCO has already scaled this pool.
function rookupgrade_10to14_maybe_scale_pool_device_health_metrics() {
    local replicapool_size=
    local device_health_metrics_size=
    device_health_metrics_size="$(kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd pool get device_health_metrics size | awk '{ print $2 }')"
    replicapool_size="$(kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd pool get replicapool size | awk '{ print $2 }')"
    if [ -n "$device_health_metrics_size" ] && [ -n "$replicapool_size" ] && [ "$replicapool_size" -gt 1 ] && [ "$device_health_metrics_size" -lt "$replicapool_size" ]; then
        log "Setting device_health_metrics pool size to $replicapool_size and min_size to 2"
        kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd pool set device_health_metrics size "$replicapool_size"
        # min_size is always 2 for greater than 1 node clusters
        kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd pool set device_health_metrics min_size 2
    fi
}
