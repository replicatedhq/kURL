#!/bin/bash
set -Eeuo pipefail
namespace="velero-roundtrip-$(date +%s)-${RANDOM}"
backup="${namespace}-backup"
restore="${namespace}-restore"
# The workload only sleeps. No command in its manifest can regenerate the payload.
function diagnostics() {
    local rc=$?
    trap - ERR
    set +e
    echo "ROUNDTRIP FAILED: namespace=$namespace backup=$backup restore=$restore status=$rc"
    kubectl get pods,pvc -n "$namespace" -o wide
    kubectl describe pod/data -n "$namespace"
    kubectl get events -n "$namespace" --sort-by=.lastTimestamp
    kubectl get backup "$backup" -n velero -o yaml
    kubectl get restore "$restore" -n velero -o yaml
    kubectl get podvolumebackups -n velero -l "velero.io/backup-name=$backup" -o yaml
    kubectl get podvolumerestores -n velero -l "velero.io/restore-name=$restore" -o yaml
    velero backup logs "$backup"
    velero restore logs "$restore"
    kubectl logs -n velero deployment/velero --tail=200
    exit "$rc"
}
trap diagnostics ERR
# kURL installs this binary from the candidate's bundled assets, including airgap.
velero version --client-only | grep 'Version: v1.18.4'
server_image=$(kubectl get deployment velero -n velero -ojsonpath='{.spec.template.spec.containers[0].image}')
[[ "$server_image" == *'/velero:v1.18.4' ]]
init_images=$(kubectl get deployment velero -n velero -ojsonpath='{range .spec.template.spec.initContainers[*]}{.image}{"\n"}{end}')
for plugin in aws gcp microsoft-azure; do
    echo "$init_images" | grep -E "/velero-plugin-for-${plugin}:v1[.]14[.]4$"
done
# kurl-util is Ubuntu-based with /bin/sh, cat, sleep and sync. Reuse the exact
# already-loaded plugin image; Never makes missing airgap packaging fail visibly.
workload_image=$(echo "$init_images" | grep '/kurl-util:' | head -1)
[[ -n "$workload_image" ]]
kubectl wait -n velero --for=jsonpath='{.status.phase}'=Available backupstoragelocation/default --timeout=300s
kubectl create namespace "$namespace"
kubectl label namespace "$namespace" kurl.sh/velero-roundtrip=true
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data
  namespace: $namespace
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: data
  namespace: $namespace
  annotations:
    backup.velero.io/backup-volumes: data
spec:
  terminationGracePeriodSeconds: 1
  containers:
  - name: data
    image: "$workload_image"
    imagePullPolicy: Never
    command: [/bin/sh, -c, "while true; do sleep 3600; done"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: data
EOF
kubectl wait -n "$namespace" --for=condition=Ready pod/data --timeout=300s
old_pvc_uid=$(kubectl get pvc/data -n "$namespace" -ojsonpath='{.metadata.uid}')
old_pv=$(kubectl get pvc/data -n "$namespace" -ojsonpath='{.spec.volumeName}')
old_pv_uid=$(kubectl get pv "$old_pv" -ojsonpath='{.metadata.uid}')
[[ -n "$old_pvc_uid" && -n "$old_pv" && -n "$old_pv_uid" ]]
[[ "$(kubectl get pv "$old_pv" -ojsonpath='{.spec.persistentVolumeReclaimPolicy}')" == Delete ]]
payload=$(mktemp)
dd if=/dev/urandom of="$payload" bs=1048576 count=1 status=none
expected_hash=$(sha256sum "$payload" | awk '{print $1}')
kubectl exec -i -n "$namespace" data -- /bin/sh -c 'cat > /data/payload; sync' < "$payload"
original_hash=$(kubectl exec -n "$namespace" data -- cat /data/payload | sha256sum | awk '{print $1}')
[[ "$original_hash" == "$expected_hash" ]]
echo "ROUNDTRIP ORIGINAL pvcUID=$old_pvc_uid pv=$old_pv pvUID=$old_pv_uid sha256=$expected_hash"
timeout 12m velero backup create "$backup" --include-namespaces "$namespace" --include-cluster-resources=false --default-volumes-to-fs-backup --snapshot-volumes=false --wait
[[ "$(kubectl get backup "$backup" -n velero -ojsonpath='{.status.phase}')" == Completed ]]
backup_errors=$(kubectl get backup "$backup" -n velero -ojsonpath='{.status.errors}')
[[ "${backup_errors:-0}" == 0 ]]
# Require exactly this pod's data-volume backup, not any other successful backup.
pvb_rows=$(kubectl get podvolumebackups -n velero -l "velero.io/backup-name=$backup" -ojsonpath='{range .items[*]}{.spec.pod.namespace}{" "}{.spec.pod.name}{" "}{.spec.volume}{" "}{.status.phase}{"\n"}{end}')
[[ "$pvb_rows" == "$namespace data data Completed" ]]
echo "ROUNDTRIP PODVOLUMEBACKUP $pvb_rows"
# Only delete the newly created, uniquely named test namespace. PV deletion is
# performed by its provisioner; do not force finalizers or directly delete PVs.
[[ "$namespace" == velero-roundtrip-* ]]
[[ "$(kubectl get namespace "$namespace" -ojsonpath='{.metadata.labels.kurl\.sh/velero-roundtrip}')" == true ]]
kubectl delete namespace "$namespace" --wait=true --timeout=300s
[[ -z "$(kubectl get namespace "$namespace" --ignore-not-found -o name)" ]]
if [[ -n "$(kubectl get pv "$old_pv" --ignore-not-found -o name)" ]]; then
    kubectl wait --for=delete pv/"$old_pv" --timeout=300s
fi
[[ -z "$(kubectl get pvc/data -n "$namespace" --ignore-not-found -o name)" ]]
[[ -z "$(kubectl get pv "$old_pv" --ignore-not-found -o name)" ]]
echo "ROUNDTRIP ORIGINAL PVC AND PV DELETED"
timeout 12m velero restore create "$restore" --from-backup "$backup" --include-namespaces "$namespace" --wait
[[ "$(kubectl get restore "$restore" -n velero -ojsonpath='{.status.phase}')" == Completed ]]
restore_errors=$(kubectl get restore "$restore" -n velero -ojsonpath='{.status.errors}')
[[ "${restore_errors:-0}" == 0 ]]
kubectl wait -n "$namespace" --for=condition=Ready pod/data --timeout=300s
pvr_rows=$(kubectl get podvolumerestores -n velero -l "velero.io/restore-name=$restore" -ojsonpath='{range .items[*]}{.spec.pod.namespace}{" "}{.spec.pod.name}{" "}{.spec.volume}{" "}{.status.phase}{"\n"}{end}')
[[ "$pvr_rows" == "$namespace data data Completed" ]]
new_pvc_uid=$(kubectl get pvc/data -n "$namespace" -ojsonpath='{.metadata.uid}')
new_pv=$(kubectl get pvc/data -n "$namespace" -ojsonpath='{.spec.volumeName}')
new_pv_uid=$(kubectl get pv "$new_pv" -ojsonpath='{.metadata.uid}')
[[ -n "$new_pvc_uid" && "$new_pvc_uid" != "$old_pvc_uid" ]]
[[ -n "$new_pv_uid" && "$new_pv_uid" != "$old_pv_uid" && "$new_pv" != "$old_pv" ]]
# First post-restore access is read-only; no workload command can rewrite data.
actual_hash=$(kubectl exec -n "$namespace" data -- cat /data/payload | sha256sum | awk '{print $1}')
[[ "$actual_hash" == "$expected_hash" ]]
echo "ROUNDTRIP PODVOLUMERESTORE $pvr_rows"
echo "ROUNDTRIP RESTORED pvcUID=$new_pvc_uid pv=$new_pv pvUID=$new_pv_uid sha256=$actual_hash"
echo "VELERO 1.18.4 DATA RESTORE VERIFIED"
rm -f "$payload"
