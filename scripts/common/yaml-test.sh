#!/bin/bash

set -e

. ./scripts/common/yaml.sh

function test_render_yaml_file_2() {
    local PROXY_ADDRESS=a
    local NO_PROXY_ADDRESSES=b
    local expects="apiVersion: apps/v1
kind: Deployment
metadata:
  name: velero
  namespace: 
spec:
  template:
    spec:
      containers:
        - name: velero
          env:
          - name: HTTP_PROXY
            value: \"a\"
          - name: HTTPS_PROXY
            value: \"a\"
          - name: NO_PROXY
            value: \"b\""
    assertEquals "preserves quotes" "$expects" "$(render_yaml_file_2 "./addons/velero/template/base/tmpl-velero-deployment-proxy.yaml")"
}

. shunit2
