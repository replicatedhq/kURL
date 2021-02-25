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
}

function openebs() {
    local src="$DIR/addons/openebs/$OPENEBS_VERSION"
    local dst="$DIR/kustomize/openebs"

    render_yaml_file "$src/tmpl-kustomization.yaml" > "$dst/kustomization.yaml"
    render_yaml_file "$src/tmpl-namespace.yaml" > "$dst/namespace.yaml"
    render_yaml_file "$src/tmpl-operator.yaml" > "$dst/operator.yaml"

    openebs_upgrade

    if [ "$OPENEBS_LOCALPV" = "1" ]; then
        render_yaml_file "$src/tmpl-localpv-storage-class.yaml" > "$dst/localpv-storage-class.yaml"
        insert_resources "$dst/kustomization.yaml" localpv-storage-class.yaml

        if [ "$OPENEBS_LOCALPV_STORAGE_CLASS" = "default" ]; then
            render_yaml_file "$src/tmpl-patch-localpv-default.yaml" > "$dst/patch-localpv-default.yaml"
            insert_patches_strategic_merge "$dst/kustomization.yaml" patch-localpv-default.yaml
        fi

        kubectl apply -k "$dst/"
    fi

    if [ "$OPENEBS_CSTOR" = "1" ]; then
        openebs_iscsi

        render_yaml_file "$src/tmpl-cstor-provisioner.yaml" > "$dst/cstor-provisioner.yaml"
        insert_resources "$dst/kustomization.yaml" cstor-provisioner.yaml

        kubectl apply -k "$dst/"

        echo "Waiting for OpenEBS operator to apply CustomResourceDefinitions"
        spinner_until 120 kubernetes_resource_exists default crd storagepoolclaims.openebs.io

        dst="$dst/storage"
        mkdir -p "$dst"
        touch "$dst/kustomization.yaml"

        # create the storage pool claim
        openebs_cstor_max_pools
        render_yaml_file "$src/tmpl-storage-pool-claim.yaml" > "$dst/storage-pool-claim.yaml"
        insert_resources "$dst/kustomization.yaml" storage-pool-claim.yaml

        # create the storage class
        OPENEBS_CSTOR_REPLICA_COUNT="$OPENEBS_CSTOR_MAX_POOLS"
        if [ $OPENEBS_CSTOR_REPLICA_COUNT -gt 3 ]; then
            OPENEBS_CSTOR_REPLICA_COUNT=3
        fi
        render_yaml_file "$src/tmpl-cstor-storage-class.yaml" > "$dst/cstor-storage-class.yaml"
        insert_resources "$dst/kustomization.yaml" cstor-storage-class.yaml
        if [ "$OPENEBS_CSTOR_STORAGE_CLASS" = "default" ]; then
            render_yaml_file "$src/tmpl-patch-cstor-default.yaml" > "$dst/patch-cstor-default.yaml"
            insert_patches_strategic_merge "$dst/kustomization.yaml" patch-cstor-default.yaml
        fi

        kubectl apply -k "$dst/"

        if ! openebs_cstor_pool_count "$OPENEBS_CSTOR_MAX_POOLS"; then
            if [ "$OPENEBS_CSTOR_MAX_POOLS" = "1" ]; then
                printf "${GREEN}Waiting for 1 disk${NC}\n"
            else
                printf "${GREEN}Waiting for ${OPENEBS_CSTOR_MAX_POOLS} disks${NC}\n"
            fi
            spinner_until 300 openebs_cstor_pool_count "$OPENEBS_CSTOR_MAX_POOLS"
        fi

        # add replicas for pre-existing volumes if needed
        openebs_cstor_scale_volumes
    fi
}

function openebs_join() {
    openebs_iscsi
}

function openebs_iscsi() {
    local src="$DIR/addons/openebs/$OPENEBS_VERSION"

    if ! systemctl list-units | grep -q iscsid; then
        printf "${YELLOW}Installing iscsid service${NC}\n"
        install_host_archives "$src"
    fi

    if ! systemctl -q is-active iscsid; then
        systemctl start iscsid
    fi

    if ! systemctl -q is-enabled iscsid; then
        systemctl enable iscsid
    fi
}


# This addon uses an automatic pool that automatically claims 1 block device per node for the pool.
# If there are unclaimed block devices on nodes that have not been incorporated into the pool, then
# increase the storage pool's maxPools setting so that a new pool can be started on the unused node
# using the unclaimed block device.
function openebs_cstor_max_pools() {
    # number of nodes that have a pool in the cstor-disk storage pool already
    OPENEBS_CSTOR_MAX_POOLS=$(kubectl -n "$OPENEBS_NAMESPACE" get cstorpools -l openebs.io/storage-pool-claim=cstor-disk --no-headers | sort | uniq | wc -l)

    # add 1 for each node that has an unclaimed block device that is not already running a pool
    while read -r blockdevicerow; do
        local nodeName=$(echo "$blockdevicerow" | awk '{ print $2 }')
        local cstorPoolsOnNodeCount=$(kubectl -n "$OPENEBS_NAMESPACE" get cstorpools -l "openebs.io/storage-pool-claim=cstor-disk,kubernetes.io/hostname=$nodeName" --no-headers | wc -l)

        if [ $cstorPoolsOnNodeCount -eq 0 ]; then
            echo "Node $nodeName is able to join the cstor-disk pool"
            OPENEBS_CSTOR_MAX_POOLS=$((OPENEBS_CSTOR_MAX_POOLS+1))
        fi
    done < <(kubectl -n "$OPENEBS_NAMESPACE" get blockdevices --no-headers 2>/dev/null | grep Unclaimed)

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
    done < <(kubectl -n $OPENEBS_NAMESPACE get cstorvolumes --no-headers 2>/dev/null | awk '{ print $1 }')
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
    local cstorPoolName="$1"
    local pvcUID="$2"
    local nodeName=$(kubectl -n "$OPENEBS_NAMESPACE" get cstorpools "$cstorPoolName" -ojsonpath='{ .metadata.labels.kubernetes\.io/hostname }')
    local cstorPoolUID=$(kubectl -n "$OPENEBS_NAMESPACE" get cstorpools "$cstorPoolName" -ojsonpath='{ .metadata.uid }')
    local pvName="pvc-$pvcUID"
    local openebsVersion=$OPENEBS_VERSION
    local newReplicaName="${pvName}-${cstorPoolName}"
    local targetIP=$(kubectl -n "$OPENEBS_NAMESPACE" get cstorvolumes "$pvName" -ojsonpath='{ .spec.targetIP }')
    local capacity=$(kubectl -n "$OPENEBS_NAMESPACE" get cstorvolumes "$pvName" -ojsonpath='{ .spec.capacity }')
    local replicaID=$(echo -n "${pvcUID}-${cstorPoolUID}" | md5sum | awk '{print toupper($1)}')

    echo "Adding replica of volume $pvName to pool $cstorPoolName on node $nodeName"

    cat <<EOF >/tmp/cvr.yaml
apiVersion: openebs.io/v1alpha1
kind: CStorVolumeReplica
metadata:
  annotations:
    cstorpool.openebs.io/hostname: "$nodeName"
    isRestoreVol: "false"
    openebs.io/storage-class-ref: |
      name: "$OPENEBS_CSTOR_STORAGE_CLASS"
  finalizers:
  - cstorvolumereplica.openebs.io/finalizer
  generation: 1
  labels:
    cstorpool.openebs.io/name: "$cstorPoolName"
    cstorpool.openebs.io/uid: "$cstorPoolUID"
    cstorvolume.openebs.io/name: "$pvName"
    openebs.io/cas-template-name: cstor-volume-create-default-${openebsVersion}
    openebs.io/persistent-volume: "$pvName"
    openebs.io/version: "$openebsVersion"
  name: "$newReplicaName"
  namespace: "$OPENEBS_NAMESPACE"
spec:
  capacity: "$capacity"
  targetIP: "$targetIP"
  replicaid: "$replicaID"
status:
  phase: Recreate
versionDetails:
  autoUpgrade: false
  desired: "$openebsVersion"
  status:
    current: "$openebsVersion"
EOF

    kubectl apply -f /tmp/cvr.yaml
    spinner_until 120 openebs_replica_is_healthy "$newReplicaName"
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

function openebs_upgrade() {
    if [ "$OPENEBS_CSTOR" != "1" ] || [ ! "$(kubectl get ns $OPENEBS_NAMESPACE 2>/dev/null)" ]; then
        # upgrades only required for cStor OR no existing install is found
        # TODO: handle namespace spec changes at the upgrade time
        return 0
    fi

    local runningVer
    runningVer=$(kubectl -n $OPENEBS_NAMESPACE get deploy openebs-provisioner -o jsonpath='{.metadata.labels.openebs\.io/version}')

    local semVerRunningList=( ${runningVer//./ } )
    local semVerInstallList=( ${OPENEBS_VERSION//./ } )

    if [[ ${semVerRunningList[0]} -lt 2 ]]; then
        bail "Upgrades from 1.x versions of openebs are not yet supported."
    fi

    return 0
}
