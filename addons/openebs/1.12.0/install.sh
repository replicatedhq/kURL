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

    if [ "$OPENEBS_CSTOR" = "1" ]; then
        openebs_iscsi
    fi
}

function openebs() {
    local src="$DIR/addons/openebs/$OPENEBS_VERSION"
    local dst="$DIR/kustomize/openebs"

    render_yaml_file "$src/tmpl-kustomization.yaml" > "$dst/kustomization.yaml"
    render_yaml_file "$src/tmpl-namespace.yaml" > "$dst/namespace.yaml"
    cp "$src/operator.yaml" "$dst/"
    cp "$src/snapshot-operator.yaml" "$dst/"

    secure_openebs
    # Identify if upgrade batch jobs are needed and apply them.
    openebs_do_upgrade

    if [ "$OPENEBS_LOCALPV" = "1" ]; then
        report_addon_start "openebs-localpv" "1.12.0"

        cp "$src/localpv-provisioner.yaml" "$dst/"
        insert_resources "$dst/kustomization.yaml" localpv-provisioner.yaml

        render_yaml_file "$src/tmpl-localpv-storage-class.yaml" > "$dst/localpv-storage-class.yaml"
        insert_resources "$dst/kustomization.yaml" localpv-storage-class.yaml

        if [ "$OPENEBS_LOCALPV_STORAGE_CLASS" = "default" ]; then
            render_yaml_file "$src/tmpl-patch-localpv-default.yaml" > "$dst/patch-localpv-default.yaml"
            insert_patches_strategic_merge "$dst/kustomization.yaml" patch-localpv-default.yaml
        fi

        kubectl apply -k "$dst/"

        report_addon_success "openebs-localpv" "1.12.0"
    fi

    if [ "$OPENEBS_CSTOR" = "1" ]; then
        report_addon_start "openebs-cstor" "1.12.0"

        cp "$src/ndm.yaml" "$dst/"
        insert_resources "$dst/kustomization.yaml" ndm.yaml

        cp "$src/cstor-provisioner.yaml" "$dst/"
        insert_resources "$dst/kustomization.yaml" cstor-provisioner.yaml

        kubectl apply -k "$dst/"

        echo "Waiting for OpenEBS operator to apply CustomResourceDefinitions"
        # wait for all crds we use in this function
        spinner_until 120 kubernetes_resource_exists default crd storagepoolclaims.openebs.io
        spinner_until 120 kubernetes_resource_exists default crd cstorpools.openebs.io
        spinner_until 120 kubernetes_resource_exists default crd blockdevices.openebs.io
        spinner_until 120 kubernetes_resource_exists default crd cstorvolumes.openebs.io
        spinner_until 120 kubernetes_resource_exists default crd cstorvolumereplicas.openebs.io

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
            spinner_until -1 openebs_cstor_pool_count "$OPENEBS_CSTOR_MAX_POOLS"
        fi

        # add replicas for pre-existing volumes if needed
        openebs_cstor_scale_volumes

        report_addon_success "openebs-cstor" "1.12.0"
    fi

    # if there is a validatingWebhookConfiguration, wait for the service to be ready
    openebs_await_admissionserver
}

function openebs_await_admissionserver() {
    logStep "Waiting for OpenEBS ValidatingWebhookConfiguration to exist"
    if spinner_until 60 kubernetes_resource_exists default validatingwebhookconfigurations openebs-validation-webhook-cfg ; then
        logStep "Waiting for OpenEBS admission controller service to be ready"
        spinner_until 120 kubernetes_service_healthy "$OPENEBS_NAMESPACE" admission-server-svc
        logSuccess "OpenEBS admission controller service is ready"
    fi
}

function openebs_join() {
    secure_openebs

    if [ "$OPENEBS_CSTOR" = "1" ]; then
        openebs_iscsi
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

            centos|rhel|ol|rocky|amzn)
                if is_rhel_9_variant ; then
                    yum_ensure_host_package iscsi-initiator-utils
                else
                    yum_install_host_archives "$src" iscsi-initiator-utils
                fi
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


# This addon uses an automatic pool that automatically claims 1 block device per node for the pool.
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
            echo "Node $nodeName is able to join the cstor-disk pool"
            OPENEBS_CSTOR_MAX_POOLS=$((OPENEBS_CSTOR_MAX_POOLS+1))
        fi
    done < <(kubectl -n "$OPENEBS_NAMESPACE" get blockdevices --no-headers 2>/dev/null | grep Unclaimed | awk '{ print $2 }')

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

function openebs_do_upgrade() {
    if [ "$OPENEBS_CSTOR" != "1" ] || [ ! "$(kubectl get ns $OPENEBS_NAMESPACE 2>/dev/null)" ]; then
        # upgrades only required for cStor OR no existing install is found
        # TODO: handle namespace spec changes at the upgrade time
        return 0
    fi

    # RE: https://github.com/openebs/openebs/tree/master/k8s/upgrades/1.x.0-1.12.x
    # Upgrading a minor version of 1.x.x requires two jobs to update pools and volumes for cStor configurations.
    local runningVer=$(kubectl -n $OPENEBS_NAMESPACE get deploy openebs-provisioner -o jsonpath='{.metadata.labels.openebs\.io/version}')

    local semVerRunningList=( ${runningVer//./ } )
    local semVerInstallList=( ${OPENEBS_VERSION//./ } )
    
    if [[ ${semVerInstallList[0]} -gt 1 ]]; then
        bail "Only upgrades up to OpenEBS 1.12.0 are tested and supported."
    fi

    upgradePools=$(openebs_check_pools)
    if [ ${semVerInstallList[1]} -gt ${semVerRunningList[1]} ] || [ ! -z $upgradePools ]; then
        local pools=$(kubectl get spc --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')
        local vols=$(kubectl get pods -l app=cstor-volume-manager -n $OPENEBS_NAMESPACE -o jsonpath='{.items[*].metadata.labels.openebs\.io/persistent-volume}')

        logSubstep "As part of the OpenEBS upgrade, pools and volumes need to be upgraded."
        logSubstep "Storage pool claims to be upgraded:"
        logSubstep "    $pools"
        logSubstep "Persistent volumes to be upgraded:"
        for vol in $vols; do
            local size=$(kubectl get pv -n $OPENEBS_NAMESPACE $vol -o jsonpath='{.spec.capacity.storage}')
            local ns=$(kubectl get pv -n $OPENEBS_NAMESPACE $vol -o jsonpath='{.spec.claimRef.namespace}')
            local claim=$(kubectl get pv -n $OPENEBS_NAMESPACE $vol -o jsonpath='{.spec.claimRef.name}')
            logSubstep "    $vol | $size | $ns/$claim"
        done

        logFail "Applications using OpenEBS-backed persistent volumes may become nonresponsive during this upgrade." 
        logFail "This upgrade may also in some failure modes result in data loss - please take a backup of any critical volumes before upgrading."
        printf "Continue? "
        if ! confirmN ; then
            bail "OpenEBS upgrade is aborted."
        fi

        openebs_upgrade_pools "$pools"
        openebs_upgrade_vols "$vols"
    fi
}

function openebs_upgrade_pools() {
    # NOTE: slightly different arguments to pass for pre and after 1.9.0.
    # Since we only support 1.6.0 -> 1.12.0 using prefixes for pre 1.9.0.
    
    # Bulk upgrade only supported for versions >=1.9.0. Have to create a job per pool.
    for pool in $1; do
        local spcCurrentVer=$(kubectl get spc $pool -o jsonpath='{.versionDetails.status.current}')
        logSubstep "Upgrading $pool from $spcCurrentVer to $OPENEBS_VERSION"
        local out_file=/tmp/openebs-pool-$pool.yaml
        cat <<UPGRADE_POOLS >$out_file
apiVersion: batch/v1
kind: Job
metadata:
  name: cstor-spc-$RANDOM
  namespace: $OPENEBS_NAMESPACE
spec:
  backoffLimit: 4
  template:
    spec:
      serviceAccountName: openebs-maya-operator
      containers:
      - name:  upgrade
        args:
        - "cstor-spc"
        - "--from-version=$spcCurrentVer"
        - "--to-version=$OPENEBS_VERSION"
        - "--spc-name=$pool"
        - "--v=4"
        env:
        - name: OPENEBS_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        tty: true
        image: openebs/m-upgrade:$OPENEBS_VERSION
        imagePullPolicy: IfNotPresent
      restartPolicy: OnFailure
UPGRADE_POOLS

        kubectl apply -f $out_file
    done
    logSubstep "OpenEBS batch job(s) to upgrade cStor pools added."
}

function openebs_upgrade_vols() {
    # NOTE: slightly different arguments to pass for pre and after 1.9.0.
    # Since we only support 1.6.0 -> 1.12.0 using prefixes for pre 1.9.0.

    # Bulk upgrade only supported for versions >=1.9.0. Have to create a job per pv.
    for pv in $1; do
        local out_file=/tmp/openebs-vol-${pv##*-}.yaml
        cat <<UPGRADE_VOLS >$out_file
apiVersion: batch/v1
kind: Job
metadata:
  name: cstor-vol-$RANDOM
  namespace: $OPENEBS_NAMESPACE
spec:
  backoffLimit: 6
  template:
    spec:
      serviceAccountName: openebs-maya-operator
      containers:
      - name:  upgrade
        args:
        - "cstor-volume"
        - "--from-version=1.6.0"
        - "--to-version=$OPENEBS_VERSION"
        - "--pv-name=$pv"
        - "--v=4"
        env:
        - name: OPENEBS_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        tty: true
        image: openebs/m-upgrade:$OPENEBS_VERSION
        imagePullPolicy: IfNotPresent
      restartPolicy: OnFailure
UPGRADE_VOLS
        kubectl apply -f $out_file
    done
    
    # TODO: Validation and user feedback of the successful completion of the jobs.
    # The jobs might take a while to run however, blocking at this point isn't necessarily the best approach.
    logSubstep "OpenEBS batch job(s) to upgrade cStor pvs added."
}

function openebs_check_pools() {
    for spc in $(kubectl get spc --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}'); do
        local spcCurrentVer=$(kubectl get spc $spc -o jsonpath='{.versionDetails.status.current}')
        if [ $(kubectl get spc $spc -o jsonpath='{.versionDetails.status.dependentsUpgraded}') == "false" ]; then
            # At least one dependant volume needs upgrade
            logSubstep "Pool $spc needs upgrade"
            echo $spcCurrentVer
        fi

        if [ $spcCurrentVer = $OPENEBS_VERSION ]; then
            # Control Plane and Pool versions are matching
            continue
        fi

        # At least 1 pool needs upgrade
        echo $spcCurrentVer
    done
}
