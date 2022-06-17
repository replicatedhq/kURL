#!/bin/sh

function openebs_pre_init() {
    if [ -z "$OPENEBS_NAMESPACE" ]; then
        OPENEBS_NAMESPACE=openebs
    fi
    if [ -z "$OPENEBS_LOCALPV_STORAGE_CLASS" ]; then
        OPENEBS_LOCALPV_STORAGE_CLASS=openebs-localpv
    fi
    if [ -z "$OPENEBS_CSTOR_STORAGE_CLASS" ]; then
        OPENEBS_CSTOR_STORAGE_CLASS=openebs-cstor
    fi
    if [ -z "$OPENEBS_CSTOR_TARGET_REPLICATION" ]; then
        OPENEBS_CSTOR_TARGET_REPLICATION="3"
    fi

    export OPENEBS_APP_VERSION="__OPENEBS_APP_VERSION__"
    export PREVIOUS_OPENEBS_VERSION="$(openebs_get_running_version)"

    openebs_bail_unsupported_upgrade
}

function openebs() {
    local src="$DIR/addons/openebs/$OPENEBS_VERSION"
    local dst="$DIR/kustomize/openebs"

    secure_openebs

    openebs_apply_crds

    # migrate resources that are changing names
    openebs_migrate_pre_helm_resources

    openebs_apply_operator

    # migrate resources that are changing names
    openebs_migrate_post_helm_resources

    openebs_apply_storageclasses
}

function openebs_apply_crds() {
    local src="$DIR/addons/openebs/$OPENEBS_VERSION/spec/crds"
    local dst="$DIR/kustomize/openebs/spec/crds"

    mkdir -p "$dst"

    cp "$src/kustomization.yaml" "$dst/"
    cp "$src/crds.yaml" "$dst/"

    kubectl apply -k "$dst/"
}

function openebs_apply_operator() {
    local src="$DIR/addons/openebs/$OPENEBS_VERSION/spec"
    local dst="$DIR/kustomize/openebs/spec"

    mkdir -p "$dst"

    render_yaml_file_2 "$src/tmpl-kustomization.yaml" > "$dst/kustomization.yaml"
    render_yaml_file_2 "$src/tmpl-namespace.yaml" > "$dst/namespace.yaml"
    cat "$src/openebs.tmpl.yaml" | sed "s/__OPENEBS_NAMESPACE__/$OPENEBS_NAMESPACE/" > "$dst/openebs.yaml"

    if [ "$OPENEBS_CSTOR" = "1" ]; then
        openebs_iscsi

        kubectl apply -k "$dst/"
        openebs_cspc_upgrade # upgrade the CSPC pools

        cat "$src/cstor.tmpl.yaml" | sed "s/__OPENEBS_NAMESPACE__/$OPENEBS_NAMESPACE/" > "$dst/cstor.yaml"
        insert_resources "$dst/kustomization.yaml" cstor.yaml
    fi

    kubectl apply -k "$dst/"

    logStep "Waiting for OpenEBS operator to apply CustomResourceDefinitions"
    spinner_until 120 kubernetes_resource_exists default crd blockdevices.openebs.io

    if [ "$OPENEBS_CSTOR" = "1" ]; then
        # wait for all crds we use in this function
        spinner_until 120 kubernetes_resource_exists default crd storagepoolclaims.openebs.io
        spinner_until 120 kubernetes_resource_exists default crd cstorpools.openebs.io
        spinner_until 120 kubernetes_resource_exists default crd cstorvolumes.openebs.io
        spinner_until 120 kubernetes_resource_exists default crd cstorvolumereplicas.openebs.io
        logSuccess "OpenEBS CustomResourceDefinitions are ready"

        openebs_cleanup_kubesystem
        openebs_upgrade_cstor
    else
        logSuccess "OpenEBS CustomResourceDefinitions are ready"
    fi
}

function openebs_apply_storageclasses() {
    # allow vendor to add custom storageclasses rather than the ones built into add-on
    if [ "$OPENEBS_CSTOR" != "1" ] && [ "$OPENEBS_LOCALPV" != "1" ]; then
        return
    fi

    local src="$DIR/addons/openebs/$OPENEBS_VERSION/spec/storage"
    local dst="$DIR/kustomize/openebs/spec/storage"

    mkdir -p "$dst"

    cp "$src/kustomization.yaml" "$dst/"

    if [ "$OPENEBS_CSTOR" = "1" ]; then
        # create the storage pool claim
        openebs_cstor_max_pools
        render_yaml_file_2 "$src/tmpl-storage-pool-claim.yaml" > "$dst/storage-pool-claim.yaml"
        insert_resources "$dst/kustomization.yaml" storage-pool-claim.yaml

        # create the storage class
        OPENEBS_CSTOR_REPLICA_COUNT="$OPENEBS_CSTOR_MAX_POOLS"
        if [ $OPENEBS_CSTOR_REPLICA_COUNT -gt 3 ]; then
            OPENEBS_CSTOR_REPLICA_COUNT=3
        fi
        render_yaml_file_2 "$src/tmpl-cstor-storage-class.yaml" > "$dst/cstor-storage-class.yaml"
        insert_resources "$dst/kustomization.yaml" cstor-storage-class.yaml
        if [ "$OPENEBS_CSTOR_STORAGE_CLASS" = "default" ]; then
            render_yaml_file_2 "$src/tmpl-patch-cstor-default.yaml" > "$dst/patch-cstor-default.yaml"
            insert_patches_strategic_merge "$dst/kustomization.yaml" patch-cstor-default.yaml
        fi
    fi

    if [ "$OPENEBS_LOCALPV" = "1" ]; then
        render_yaml_file_2 "$src/tmpl-localpv-storage-class.yaml" > "$dst/localpv-storage-class.yaml"
        insert_resources "$dst/kustomization.yaml" localpv-storage-class.yaml

        if [ "$OPENEBS_LOCALPV_STORAGE_CLASS" = "default" ]; then
            render_yaml_file_2 "$src/tmpl-patch-localpv-default.yaml" > "$dst/patch-localpv-default.yaml"
            insert_patches_strategic_merge "$dst/kustomization.yaml" patch-localpv-default.yaml
        fi
    fi

    kubectl apply -k "$dst/"

    if [ "$OPENEBS_CSTOR" = "1" ]; then
        if ! openebs_cstor_pool_count "$OPENEBS_CSTOR_MAX_POOLS"; then
            if [ "$OPENEBS_CSTOR_MAX_POOLS" = "1" ]; then
                logStep "Waiting for 1 disk"
            else
                logStep "Waiting for ${OPENEBS_CSTOR_MAX_POOLS} disks"
            fi
            spinner_until 300 openebs_cstor_pool_count "$OPENEBS_CSTOR_MAX_POOLS"
            logSuccess "Disks are ready"
        fi

        # add replicas for pre-existing volumes if needed
        openebs_cstor_scale_volumes
    fi
}

function openebs_join() {
    secure_openebs

    if [ "$OPENEBS_CSTOR" = "1" ]; then
        openebs_iscsi
    fi
}

function openebs_get_running_version() {
    if kubectl get ns "$OPENEBS_NAMESPACE" >/dev/null 2>&1 ; then
        kubectl -n "$OPENEBS_NAMESPACE" get deploy openebs-provisioner -o jsonpath='{.metadata.labels.openebs\.io/version}' 2>/dev/null
    fi
}

function openebs_bail_unsupported_upgrade() {
    if [ -z "$PREVIOUS_OPENEBS_VERSION" ]; then
        return 0
    fi

    semverCompare "$PREVIOUS_OPENEBS_VERSION" "2.0.0"
    if [ "$SEMVER_COMPARE_RESULT" = "-1" ]; then
        logFail "Upgrades from versions prior to 2.x of OpenEBS are unsupported."
        bail "Please first upgrade to 2.6.0."
    fi
}

function secure_openebs() {
    mkdir -p /var/openebs
    chmod 700 /var/openebs
}

function openebs_iscsi() {
    local src="$DIR/addons/openebs/$OPENEBS_VERSION"

    if ! systemctl list-units | grep -q iscsid; then
        case "$LSB_DIST" in
            ubuntu)
                dpkg_install_host_archives "$src" open-iscsi
                ;;

            centos|rhel|amzn|ol)
                yum_install_host_archives "$src" iscsi-initiator-utils
                ;;
        esac
    fi

    if ! systemctl -q is-active iscsid; then
        systemctl start iscsid
    fi

    if ! systemctl -q is-enabled iscsid; then
        systemctl enable iscsid
    fi
}

# This add-on uses an automatic pool that automatically claims 1 block device per node for the pool.
# If there are unclaimed block devices on nodes that have not been incorporated into the pool, then
# increase the storage pool's maxPools setting so that a new pool can be started on the unused node
# using the unclaimed block device.
function openebs_cstor_max_pools() {
    # number of nodes that have a pool in the cstor-disk storage pool already
    OPENEBS_CSTOR_MAX_POOLS=$(kubectl -n "$OPENEBS_NAMESPACE" get cstorpools -l openebs.io/storage-pool-claim=cstor-disk --no-headers | sort | uniq | wc -l)

    # add 1 for each node that has an unclaimed block device that is not already running a pool
    local nodeName=
    while read -r nodeName; do
        local cstorPoolsOnNodeCount=$(kubectl -n "$OPENEBS_NAMESPACE" get cstorpools -l "openebs.io/storage-pool-claim=cstor-disk,kubernetes.io/hostname=$nodeName" --no-headers | wc -l)

        if [ $cstorPoolsOnNodeCount -eq 0 ]; then
            logSuccess "Node $nodeName is able to join the cstor-disk pool"
            OPENEBS_CSTOR_MAX_POOLS=$((OPENEBS_CSTOR_MAX_POOLS+1))
        fi
    done < <(kubectl -n "$OPENEBS_NAMESPACE" get blockdevices --no-headers 2>/dev/null | grep Unclaimed | awk '{ print $2 }' | sort | uniq)

    if [ $OPENEBS_CSTOR_MAX_POOLS -lt 1 ]; then
        OPENEBS_CSTOR_MAX_POOLS=1
    fi
}

function openebs_cstor_scale_volumes() {
    local targetReplication="$OPENEBS_CSTOR_TARGET_REPLICATION"
    local cstorPoolCount=$(kubectl -n "$OPENEBS_NAMESPACE" get cstorpools -l openebs.io/storage-pool-claim=cstor-disk --no-headers 2>/dev/null | wc -l)
    if [ "$cstorPoolCount" -lt "$targetReplication" ]; then
        targetReplication="$cstorPoolCount"
    fi

    while read -r cstorVolumeName; do
        local volumeStorageClass=$(kubectl -n "$OPENEBS_NAMESPACE" get cstorvolume "$cstorVolumeName" -ojsonpath='{ .metadata.annotations.openebs\.io/storage-class-ref }' | grep name | awk '{ print $2 }')
        local volumeReplicaCount=$(kubectl -n "$OPENEBS_NAMESPACE" get cstorvolumereplicas -l "cstorvolume.openebs.io/name=$cstorVolumeName" --no-headers | wc -l)

        if [ "$volumeStorageClass" = "$OPENEBS_CSTOR_STORAGE_CLASS" ] && [ "$volumeReplicaCount" -lt "$targetReplication" ]; then
            openebs_cstor_replicate "$cstorVolumeName" "$targetReplication"
        fi
    done < <(kubectl -n "$OPENEBS_NAMESPACE" get cstorvolumes --no-headers 2>/dev/null | awk '{ print $1 }')
}

# Add replicas to a volume
function openebs_cstor_replicate() {
    local cstorVolumeName="$1"
    local targetReplication="$2"
    local additionalReplicaCount="$(( $targetReplication - $volumeReplicaCount ))"
    local cstorPoolCount=$(kubectl -n "$OPENEBS_NAMESPACE" get cstorpools -l openebs.io/storage-pool-claim=cstor-disk --no-headers 2>/dev/null | wc -l)
    local pvcUID=$(echo "$cstorVolumeName" | sed 's/pvc-//')

    # increase the desiredReplicationFactor on the cstorvolume, otherwise new replica status will be
    # Offline rather than Healthy
    kubectl -n "$OPENEBS_NAMESPACE" get cstorvolumes "$cstorVolumeName" -oyaml | sed "s/desiredReplicationFactor.*/desiredReplicationFactor: ${targetReplication}/" > "/tmp/${cstorVolumeName}.yaml"
    kubectl apply -f "/tmp/${cstorVolumeName}.yaml"

    # find an eligible pool that does not have a replica of the volume
    while read -r cstorPoolName; do
        if openebs_cstor_pool_has_replica_of_volume "$cstorPoolName" "$cstorVolumeName"; then
            continue
        fi
        openebs_cstor_add_replica "$cstorPoolName" "$pvcUID"
        additionalReplicaCount=$((additionalReplicaCount-1))
        if [ $additionalReplicaCount -eq 0 ]; then
            return 0
        fi
    done < <(kubectl -n $OPENEBS_NAMESPACE get cstorpools -l openebs.io/storage-pool-claim=cstor-disk --no-headers 2>/dev/null | awk '{ print $1 }' | shuf)
}

function openebs_cstor_pool_has_replica_of_volume() {
    local cstorPoolName="$1"
    local cstorVolumeName="$2"

    kubectl -n "$OPENEBS_NAMESPACE" get cstorvolumereplicas -l "cstorpool.openebs.io/name=$cstorPoolName" | grep -q "$cstorVolumeName"
}

function openebs_cstor_add_replica() {
    local src="$DIR/addons/openebs/$OPENEBS_VERSION/spec/misc"
    local dst="$DIR/kustomize/openebs/spec/misc"

    local cstorPoolName="$1"
    local pvcUID="$2"
    local nodeName=$(kubectl -n "$OPENEBS_NAMESPACE" get cstorpools "$cstorPoolName" -ojsonpath='{ .metadata.labels.kubernetes\.io/hostname }')
    local cstorPoolUID=$(kubectl -n "$OPENEBS_NAMESPACE" get cstorpools "$cstorPoolName" -ojsonpath='{ .metadata.uid }')
    local pvName="pvc-$pvcUID"
    local openebsVersion=$OPENEBS_APP_VERSION
    local newReplicaName="${pvName}-${cstorPoolName}"
    local targetIP=$(kubectl -n "$OPENEBS_NAMESPACE" get cstorvolumes "$pvName" -ojsonpath='{ .spec.targetIP }')
    local capacity=$(kubectl -n "$OPENEBS_NAMESPACE" get cstorvolumes "$pvName" -ojsonpath='{ .spec.capacity }')
    local replicaID=$(echo -n "${pvcUID}-${cstorPoolUID}" | md5sum | awk '{print toupper($1)}')

    logStep "Adding replica of volume $pvName to pool $cstorPoolName on node $nodeName"

    render_yaml_file_2 "$src/tmpl-cstor-volume-replica.yaml" > "$dst/cstor-volume-replica.yaml"

    kubectl apply -f "$dst/cstor-volume-replica.yaml"
    spinner_until 120 openebs_replica_is_healthy "$newReplicaName"
    logSuccess "Replica added successfully"
}

function openebs_replica_is_healthy() {
    local replicaName="$1"
    local status=$(kubectl -n "$OPENEBS_NAMESPACE" get cstorvolumereplica "$replicaName" -ojsonpath='{ .status.phase }')
    [ "$status" = "Healthy" ]
}

function openebs_cstor_pool_count() {
    local target="$1"
    local actual=$(kubectl -n "$OPENEBS_NAMESPACE" get cstorpools -l openebs.io/storage-pool-claim=cstor-disk --no-headers 2>/dev/null | wc -l)
    [ $actual -ge $target ]
}

function openebs_cspc_upgrade() {
    # start upgrade process - see https://github.com/openebs/upgrade/blob/v2.12.2/docs/upgrade.md
    kubectl delete csidriver cstor.csi.openebs.io || true

    openebs_upgrade_pools
    return 0
}

function openebs_cleanup_kubesystem() {
    # cleanup old kube-system statefulsets
    # https://github.com/openebs/upgrade/blob/v2.12.2/docs/upgrade.md#prerequisites-1
    kubectl -n kube-system delete sts openebs-cstor-csi-controller 2>/dev/null || true
    kubectl -n kube-system delete ds openebs-cstor-csi-node 2>/dev/null || true
    kubectl -n kube-system delete sa openebs-cstor-csi-controller-sa,openebs-cstor-csi-node-sa 2>/dev/null || true
}

function openebs_upgrade_pools() {
    # upgrade job from https://github.com/openebs/upgrade/blob/v2.12.2/examples/upgrade/cstor-cspc.yaml

    if [ -z "$PREVIOUS_OPENEBS_VERSION" ] || [ "$PREVIOUS_OPENEBS_VERSION" = "$OPENEBS_APP_VERSION" ]; then
        return 0 # no upgrade needed
    fi

    local src="$DIR/addons/openebs/$OPENEBS_VERSION/spec/misc"
    local dst="$DIR/kustomize/openebs/spec/misc"

    local pools
    pools=$(kubectl get cspc --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')

    local pools_list=
    for value in $pools_list; do
        printf -v pools_list "$pools_list\n        - \"$value\""
    done

    logStep "Upgrading CSPC pools $pools from $PREVIOUS_OPENEBS_VERSION to $OPENEBS_APP_VERSION"
    local jobname="cstor-cspc-upgrade-$(echo $RANDOM | md5sum | head -c 7; echo)"
    render_yaml_file_2 "$src/tmpl-openebs-pool-upgrade.yaml" > "$dst/openebs-pool-upgrade.yaml"

    kubectl apply -f "$dst/openebs-pool-upgrade.yaml"
    logStep "Waiting for $jobname job"
    spinner_until 240 job_is_completed "$OPENEBS_NAMESPACE" "$jobname"
    logSuccess "OpenEBS batch job to upgrade cStor pools completed."
}

function openebs_upgrade_cstor() {
    # upgrade job from https://github.com/openebs/upgrade/blob/v2.12.2/examples/upgrade/cstor-volume.yaml

    if [ -z "$PREVIOUS_OPENEBS_VERSION" ] || [ "$PREVIOUS_OPENEBS_VERSION" = "$OPENEBS_APP_VERSION" ]; then
        return 0 # no upgrade needed
    fi

    local src="$DIR/addons/openebs/$OPENEBS_VERSION/spec/misc"
    local dst="$DIR/kustomize/openebs/spec/misc"

    local pvs
    pvs=$(kubectl get pv --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')

    local volumes_list=
    for value in $pvs; do
        printf -v volumes_list "$volumes_list\n        - \"$value\""
    done

    logStep "Upgrading cStor volumes $pvs from $PREVIOUS_OPENEBS_VERSION to $OPENEBS_APP_VERSION"
    local jobname="cstor-volume-upgrade-$(echo $RANDOM | md5sum | head -c 7; echo)"
    render_yaml_file_2 "$src/tmpl-openebs-volume-upgrade.yaml" > "$dst/openebs-volume-upgrade.yaml"

    kubectl apply -f "$dst/openebs-volume-upgrade.yaml"
    logStep "Waiting for $jobname job"
    spinner_until 240 job_is_completed "$OPENEBS_NAMESPACE" "$jobname"
    logSuccess "OpenEBS batch job to upgrade cStor volumes completed."
}

function openebs_migrate_pre_helm_resources() {
    # name changed from maya-apiserver-service > openebs-apiservice
    kubectl -n "$OPENEBS_NAMESPACE" delete service maya-apiserver-service 2>/dev/null || true
    # name changed from cvc-operator-service > openebs-cstor-cvc-operator-svc
    kubectl -n "$OPENEBS_NAMESPACE" delete service cvc-operator-service 2>/dev/null || true
    # name changed from maya-apiserver >openebs-apiserver
    kubectl -n "$OPENEBS_NAMESPACE" delete deployment maya-apiserver 2>/dev/null || true
    # name changed from cspc-operator > openebs-cstor-cspc-operator
    kubectl -n "$OPENEBS_NAMESPACE" delete deployment cspc-operator 2>/dev/null || true
    # name changed from cvc-operator > openebs-cstor-cvc-operator
    kubectl -n "$OPENEBS_NAMESPACE" delete deployment cvc-operator 2>/dev/null || true
}

function openebs_migrate_post_helm_resources() {
    # name changed from openebs-maya-operator > openebs
    kubectl delete serviceaccount openebs-maya-operator 2>/dev/null || true
    # name changed from openebs-maya-operator > openebs
    kubectl delete clusterrole openebs-maya-operator 2>/dev/null || true
    # name changed from openebs-maya-operator > openebs
    kubectl delete clusterrolebinding openebs-maya-operator 2>/dev/null || true
}
