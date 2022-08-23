#!/bin/bash

MASTER_NODE=$1

job_name=""
if [[ $MASTER_NODE == "master" ]]; then
    job_name="kube-bench-master"
   echo "Running job-master.yaml from kube-bench repo"
   curl -L https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job-master.yaml | kubectl create -f -
else
    job_name="kube-bench-node"
   echo "Running job-node.yaml from kube-bench repo"
   curl -L https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job-node.yaml | kubectl create -f -
fi

# wait for job to finish
until kubectl get jobs $job_name -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' | grep -q True ; do sleep 1 ; done

# dump logs
kubectl logs job/$job_name
