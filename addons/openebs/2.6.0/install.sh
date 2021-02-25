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
    cp "$src/operator.yaml" "$dst/"

    openebs_spc_cspc_migration

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

        kubectl apply -k "$dst/"
        openebs_cspc_upgrade # upgrade the CSPC pools

        cp "$src/cstor-provisioner.yaml" "$dst/"
        insert_resources "$dst/kustomization.yaml" cstor-provisioner.yaml

        kubectl apply -k "$dst/"

        echo "Waiting for OpenEBS operator to apply CustomResourceDefinitions"
        spinner_until 120 kubernetes_resource_exists default crd storagepoolclaims.openebs.io

        openebs_cleanup_kubesystem
        openebs_upgrade_cstor

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

function openebs_spc_cspc_migration() {
    if [ "$OPENEBS_CSTOR" != "1" ] || [ ! "$(kubectl get ns $OPENEBS_NAMESPACE 2>/dev/null)" ]; then
        # upgrades only required for cStor OR no existing install is found
        # TODO: handle namespace spec changes at the upgrade time
        return 0
    fi

    local runningVer
    runningVer=$(kubectl -n $OPENEBS_NAMESPACE get deploy openebs-provisioner -o jsonpath='{.metadata.labels.openebs\.io/version}')

    local semVerRunningList=( ${runningVer//./ } )
    local semVerInstallList=( ${OPENEBS_VERSION//./ } )

    if [[ ${semVerRunningList[0]} -eq 2 ]] && [[ ${semVerRunningList[1]} -eq 6 ]]; then
      # this is already up to date
      return 0
    fi

    if [[ ${semVerRunningList[0]} -lt 2 ]] && [[ ${semVerRunningList[1]} -lt 12 ]]; then
        bail "Upgrades from pre-1.12 versions of openebs are not yet supported."
    fi

    openebs_spc_to_cspc
}

function openebs_cspc_upgrade() {
    # start upgrade process - see https://github.com/openebs/upgrade/blob/v2.6.0/docs/upgrade.md
    kubectl delete csidriver cstor.csi.openebs.io

    openebs_upgrade_pools
    return 0
}

function openebs_cleanup_kubesystem() {
  # cleanup old kube-system statefulsets
  # https://github.com/openebs/upgrade/blob/v2.6.0/docs/upgrade.md#prerequisites-1
  kubectl -n kube-system delete sts openebs-cstor-csi-controller
  kubectl -n kube-system delete ds openebs-cstor-csi-node
  kubectl -n kube-system delete sa openebs-cstor-csi-controller-sa,openebs-cstor-csi-node-sa
}

function openebs_spc_to_cspc() {
    # upgrade job from https://github.com/openebs/upgrade/blob/v2.6.0/examples/migrate/spc-migration.yaml

    local pools
    pools=$(kubectl get spc --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')

    for pool in $pools; do
        local spcCurrentVer=$(kubectl get spc $pool -o jsonpath='{.versionDetails.status.current}')
        logSubstep "Upgrading $pool from SPC to CSPC"
        local out_file=/tmp/openebs-spc-cspc-$pool.yaml
        cat <<UPGRADE_POOLS >$out_file
apiVersion: batch/v1
kind: Job
metadata:
  # the name can be of the form migrate-<spc-name>
  name: migrate-$pool
  namespace: $OPENEBS_NAMESPACE
spec:
  backoffLimit: 0
  template:
    spec:
      serviceAccountName: openebs-maya-operator
      containers:
      - name:  migrate
        args:
        - "cstor-spc"
        # name of the spc that is to be migrated
        - "--spc-name=$pool"
        # optional flag to rename the spc to a specific name
        # - "--cspc-name=sparse-claim-migrated"

        #Following are optional parameters
        #Log Level
        - "--v=4"
        #DO NOT CHANGE BELOW PARAMETERS
        env:
        - name: OPENEBS_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        tty: true
        # the version of the image should be same the
        # version of cstor-operator installed.
        image: openebs/migrate:$spcCurrentVer
      restartPolicy: Never
UPGRADE_POOLS

        kubectl apply -f $out_file

        spinner_job_completed migrate-$pool
    done
    logSubstep "OpenEBS job(s) to upgrade from SPC to CSPC pools completed."
}

function openebs_upgrade_pools() {
    # upgrade job from https://github.com/openebs/upgrade/blob/v2.6.0/examples/upgrade/cstor-cspc.yaml

    local runningVer
    runningVer=$(kubectl -n $OPENEBS_NAMESPACE get deploy openebs-provisioner -o jsonpath='{.metadata.labels.openebs\.io/version}')

    local pools
    pools=$(kubectl get cspc --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')

    local poolList
    for value in $pools; do
      poolList+="        - \"$value\"\n"
    done

    logSubstep "Upgrading cspc pools $pools from $runningVer to $OPENEBS_VERSION"
    local out_file=/tmp/openebs-pool-upgrade.yaml
    cat <<UPGRADE_POOLS >$out_file
apiVersion: batch/v1
kind: Job
metadata:
  name: cstor-cspc-upgrade
  namespace: $OPENEBS_NAMESPACE
spec:
  backoffLimit: 4
  template:
    spec:
      serviceAccountName: openebs-maya-operator
      containers:
      - name:  upgrade
        args:
        - "cstor-cspc"

        # --from-version is the current version of the pool
        - "--from-version=$runningVer"

        # --to-version is the version desired upgrade version
        - "--to-version=2.6.0"
        # if required the image prefix of the pool deployments can be
        # changed using the flag below, defaults to whatever was present on old
        # deployments.
        #- "--to-version-image-prefix=openebs/"
        # if required the image tags for pool deployments can be changed
        # to a custom image tag using the flag below,
        # defaults to the --to-version mentioned above.
        #- "--to-version-image-tag=ci"

        # VERIFY that you have provided the correct list of CSPC Names
$poolList

        # Following are optional parameters
        # Log Level
        - "--v=4"
        # DO NOT CHANGE BELOW PARAMETERS
        env:
        - name: OPENEBS_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        tty: true

        # the image version should be same as the --to-version mentioned above
        # in the args of the job
        image: openebs/upgrade:2.6.0
        imagePullPolicy: IfNotPresent
      restartPolicy: OnFailure
UPGRADE_POOLS
    kubectl apply -f $out_file
    spinner_job_completed "cstor-cspc-upgrade"
    logSubstep "OpenEBS batch job to upgrade cStor pools completed."
}


function openebs_upgrade_cstor() {
    # upgrade job from https://github.com/openebs/upgrade/blob/v2.6.0/examples/upgrade/cstor-volume.yaml

    local runningVer
    runningVer=$(kubectl -n $OPENEBS_NAMESPACE get deploy openebs-provisioner -o jsonpath='{.metadata.labels.openebs\.io/version}')

    local pvs
    pvs=$(kubectl get pv --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')

    local pvList
    for value in $pvs; do
      pvList+="        - \"$value\"\n"
    done

    logSubstep "Upgrading cstor volumes $pvs from $runningVer to $OPENEBS_VERSION"
    local out_file=/tmp/openebs-volume-upgrade.yaml
    cat <<UPGRADE_VOLUME >$out_file
apiVersion: batch/v1
kind: Job
metadata:
  name: cstor-volume-upgrade
  namespace: $OPENEBS_NAMESPACE
spec:
  backoffLimit: 4
  template:
    spec:
      serviceAccountName: openebs-maya-operator
      containers:
      - name:  upgrade
        args:
        - "cstor-volume"

        # --from-version is the current version of the volume
        - "--from-version=$runningVer"

        # --to-version is the version desired upgrade version
        - "--to-version=2.6.0"
        # if required the image prefix of the volume deployments can be
        # changed using the flag below, defaults to whatever was present on old
        # deployments.
        #- "--to-version-image-prefix=openebs/"
        # if required the image tags for volume deployments can be changed
        # to a custom image tag using the flag below,
        # defaults to the --to-version mentioned above.
        #- "--to-version-image-tag=ci"

        # VERIFY that you have provided the correct list of volume Names
$pvList

        # Following are optional parameters
        # Log Level
        - "--v=4"
        # DO NOT CHANGE BELOW PARAMETERS
        env:
        - name: OPENEBS_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        tty: true

        # the image version should be same as the --to-version mentioned above
        # in the args of the job
        image: openebs/upgrade:2.6.0
        imagePullPolicy: IfNotPresent
      restartPolicy: OnFailure
UPGRADE_VOLUME

    kubectl apply -f $out_file
    spinner_job_completed "cstor-volume-upgrade"
    logSubstep "OpenEBS batch job to upgrade cstor volumes completed."
}
