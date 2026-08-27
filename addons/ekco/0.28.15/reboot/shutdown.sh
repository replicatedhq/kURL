#!/bin/bash

export KUBECONFIG=/etc/kubernetes/kubelet.conf

# KURL_HOSTNAME_OVERRIDE can be used to override the node name used by kURL
KURL_HOSTNAME_OVERRIDE=${KURL_HOSTNAME_OVERRIDE:-}

# kubernetes_init_hostname sets the HOSTNAME variable to equal the hostname binary output. If
# KURL_HOSTNAME_OVERRIDE is set, it will be used instead. Otherwise, if the kubelet flags file
# contains a --hostname-override flag, it will be used instead.
function kubernetes_init_hostname() {
    export HOSTNAME
    if [ -n "$KURL_HOSTNAME_OVERRIDE" ]; then
        HOSTNAME="$KURL_HOSTNAME_OVERRIDE"
    fi
    local hostname_override=
    hostname_override="$(kubernetes_get_kubelet_hostname_override)"
    if [ -n "$hostname_override" ] ; then
        HOSTNAME="$hostname_override"
    fi
    HOSTNAME="$(hostname | tr '[:upper:]' '[:lower:]')"
}

# kubernetes_get_kubelet_hostname_override returns the value of the --hostname-override flag in the
# kubelet env flags file.
function kubernetes_get_kubelet_hostname_override() {
    if [ -f "$KUBELET_FLAGS_FILE" ]; then
        grep -o '\--hostname-override=[^" ]*' "$KUBELET_FLAGS_FILE" | awk -F'=' '{ print $2 }'
    fi
}

# get_local_node_name returns the name of the current node.
function get_local_node_name() {
    echo "$HOSTNAME"
}

function main() {
    kubernetes_init_hostname

    kubectl cordon "$(get_local_node_name)"

    nodePodNames=$(kubectl get pods --all-namespaces --field-selector spec.nodeName="$HOSTNAME" -ojsonpath='{ range .items[*]}{.metadata.name}{"\t"}{.metadata.namespace}{"\n"}{end}' )
    while read -r pod; do
        if [ -z "$pod" ]; then
            continue
        fi

        # skip pods in kube-system, rook-ceph, openebs, and longhorn-system namespaces
        ns=$(echo "$pod" | awk '{ print $2 }')
        if [ "$ns" == "kube-system" ] || [ "$ns" == "rook-ceph" ] || [ "$ns" == "openebs" ] || [ "$ns" == "longhorn-system" ]; then
            continue
        fi

        kubectl delete pod "$(echo "$pod" | awk '{ print $1 }')" --namespace="$(echo "$pod" | awk '{ print $2 }')" --wait=false
    done < <(echo "$nodePodNames")

    # while there are still pods with PVCs mounted
    while lsblk | grep -q "\/var\/lib\/kubelet\/pods\/.*\/pvc-"; do
        echo "Waiting for pods to unmount PVCs"
        sleep 1
    done

    while grep -q ':6789:/' /proc/mounts; do
        echo "Waiting for Ceph shared filesystems to unmount"
        sleep 1
    done

    # remove ceph-operator and mds pods from this node so they can continue to service the cluster
    thisHost=$(get_local_node_name)
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
}

main "$@"
