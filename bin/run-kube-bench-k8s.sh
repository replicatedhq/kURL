#!/bin/bash

NODE=$1

function horizontal_rule {
  printf "%$(tput cols)s\n"|tr " " "-"
}

job_name=""
if [[ $NODE == "master" ]]; then
  job_name="kube-bench-master"
  echo "Running job-master.yaml from kube-bench repo"
  curl -Ls https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job-master.yaml | kubectl create -f -
  horizontal_rule
elif [[ $NODE == "worker" ]]; then
  job_name="kube-bench-node"
  echo "Running job-node.yaml from kube-bench repo"
  curl -Ls https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job-node.yaml | kubectl create -f -
  horizontal_rule
else
  job_name="kube-bench-master kube-bench-node"
  echo "Running CIS kubernetes benchmark test for master and worker nodes"
  curl -Ls https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job-master.yaml | kubectl create -f -
  curl -Ls https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job-node.yaml | kubectl create -f -
  horizontal_rule
fi

for job in $job_name; do
  # wait for job to finish
  until kubectl get job "$job" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' | grep -q True ; do sleep 1 ; done
  # dump logs
  kubectl logs job/"$job"
done

horizontal_rule
echo "kube-bench test completed."

