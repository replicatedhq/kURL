#!/bin/bash

export KUBECONFIG=/etc/kubernetes/kubelet.conf

# wait for Kubernets API
master=$(cat /etc/kubernetes/kubelet.conf | grep server | awk '{ print $2 }')
while [ "$(curl --noproxy "*" -sk $master/healthz)" != "ok" ]; do
        sleep 1
done

kubectl uncordon $(hostname | tr '[:upper:]' '[:lower:]')
