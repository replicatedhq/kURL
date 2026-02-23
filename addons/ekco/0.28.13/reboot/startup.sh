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
    # On first install on additional nodes the node is not yet joined to the cluster
    if [ ! -e /etc/kubernetes/kubelet.conf ]; then
        exit 0
    fi

    kubernetes_init_hostname

    # wait for Kubernetes API
    master=$(grep ' server: ' /etc/kubernetes/kubelet.conf | awk '{ print $2 }')
    while [ "$(curl --noproxy "*" -sk "$master/healthz")" != "ok" ]; do
        sleep 1
    done

    kubectl uncordon "$(get_local_node_name)"
}

main "$@"
