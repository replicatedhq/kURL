#!/bin/bash

export KUBECONFIG=/etc/kubernetes/kubelet.conf

kubectl cordon "$(hostname | tr '[:upper:]' '[:lower:]')"

allPodUIDs=$(kubectl get pods --all-namespaces -ojsonpath='{ range .items[*]}{.metadata.name}{"\t"}{.metadata.uid}{"\t"}{.metadata.namespace}{"\n"}{end}' )

# delete local pods with PVCs
while read -r dev; do
    uid=$(echo "$dev" | grep -Eo "pods\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | sed 's/pods\///')
    pod=$(echo "${allPodUIDs[*]}" | grep "$uid")
    kubectl delete pod "$(echo "$pod" | awk '{ print $1 }')" --namespace="$(echo "$pod" | awk '{ print $3 }')" --wait=false
done < <(lsblk | grep "\/var\/lib\/kubelet\/pods\/.*\/pvc-")

# delete local pods using the Ceph filesystem
while read -r uid; do
    pod=$(kubectl get pods --all-namespaces -ojsonpath='{ range .items[*]}{.metadata.name}{"\t"}{.metadata.uid}{"\t"}{.metadata.namespace}{"\n"}{end}' | grep "$uid" )
    kubectl delete pod "$(echo "$pod" | awk '{ print $1 }')" --namespace="$(echo "$pod" | awk '{ print $3 }')" --wait=false
done < <(grep ':6789:/' /proc/mounts | grep -v globalmount | awk '{ print $2 }' | awk -F '/' '{ print $6 }')

# while there are still pods with PVCs mounted
while [ -n "$(lsblk | grep "\/var\/lib\/kubelet\/pods\/.*\/pvc-")" ]; do
    echo "Waiting for pods to unmount PVCs"
    sleep 1
done

while grep -q ':6789:/' /proc/mounts; do
    echo "Waiting for Ceph shared filesystems to unmount"
    sleep 1
done

# remove ceph-operator and mds pods from this node so they can continue to service the cluster
thisHost=$(hostname | tr '[:upper:]' '[:lower:]')
while read -r row; do
    podName=$(echo "$row" | awk '{ print $1 }')
    ns=$(echo "$row" | awk '{ print $2 }')

    if echo "$podName" | grep -q "rook-ceph-operator"; then
        kubectl -n "$ns" delete pod "$podName"
    fi
    if echo "$podName" | grep -q "rook-ceph-mds-rook-shared-fs"; then
        kubectl -n "$ns" delete pod "$podName"
    fi
done < <(kubectl get pods --all-namespaces -ojsonpath='{ range .items[*]}{.metadata.name}{"\t"}{.metadata.namespace}{"\t"}{.spec.nodeName}{"\n"}{end}' | grep -E "${thisHost}$")
