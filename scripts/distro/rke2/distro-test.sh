#!/bin/bash

set -e

. ./scripts/distro/rke2/distro.sh

function test_rke2_discover_private_ip() {
    function cat() {
        echo "apiVersion: v1
kind: Pod
metadata:
  annotations:
    etcd.k3s.io/initial: '{\"initial-advertise-peer-urls\":\"https://10.138.0.109:2380\",\"initial-cluster\":\"ethan-rke2-dev-4f6ea88b=https://10.138.0.109:2380\",\"initial-cluster-state\":\"new\"}'
  labels:
    component: etcd
    tier: control-plane
  name: etcd
  namespace: kube-system
spec:
  containers:
  - command:
    - etcd
    - --config-file=/var/lib/rancher/rke2/server/db/etcd/config"
    }
    export cat

    HOSTNAME=ethan-rke2-dev
    assertEquals "rke2_discover_private_ip" "10.138.0.109" "$(rke2_discover_private_ip)"
}

. shunit2
