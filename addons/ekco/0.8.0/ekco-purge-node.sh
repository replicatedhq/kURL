#!/bin/bash

set -e

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"

namespace=kurl
pod="$(kubectl get pods -n "$namespace" -l app=ekc-operator --field-selector=status.phase=Running --no-headers 2>/dev/null | awk 'NR == 1 {print $1}')"

if [ -z "$pod" ]; then
    printf "[error] no running EKCO pods found\n\n" 1>&2
    (set -x; kubectl get pods -n "$namespace" -l app=ekc-operator 1>&2)
    exit 1
fi

kubectl exec -n "$namespace" -it "$pod" -- ekco purge-node $@
