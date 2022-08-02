#!/bin/bash

# On first install on additional nodes the node is not yet joined to the cluster
if [ ! -e /etc/kubernetes/kubelet.conf ]; then
    exit 0
fi

export KUBECONFIG=/etc/kubernetes/kubelet.conf

# wait for Kubernetes API
master=$(cat /etc/kubernetes/kubelet.conf | grep ' server:' | awk '{ print $2 }')
while [ "$(curl --noproxy "*" -sk $master/healthz)" != "ok" ]; do
        sleep 1
done

kubectl uncordon $(hostname | tr '[:upper:]' '[:lower:]')
