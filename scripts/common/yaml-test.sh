#!/bin/bash

set -e

# shellcheck disable=SC1091
. ./scripts/common/common.sh
# shellcheck disable=SC1091
. ./scripts/common/yaml.sh

function test_render_yaml_file_2() {
    # shellcheck disable=SC2034
    local PROXY_ADDRESS=a
    # shellcheck disable=SC2034
    local PROXY_HTTPS_ADDRESS=b
    # shellcheck disable=SC2034
    local NO_PROXY_ADDRESSES=c
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
            value: \"b\"
          - name: NO_PROXY
            value: \"c\""
    assertEquals "preserves quotes" "$expects" "$(render_yaml_file_2 "./addons/velero/template/base/tmpl-velero-deployment-proxy.yaml")"
}

function test_render_yaml_file_2_file_not_found() {
    assertEquals "file not found returns an error" "1" "$(render_yaml_file_2 "./blah" 2>/dev/null ; echo "$?")"
}

function test_insert_bases_kubectl_120() {
    local tmpdir=
    tmpdir="$(mktemp -d)"

    kubectl(){
        echo "Client Version: v1.20.0"
    }

    echo -e "resources:\n- r1\n\nbases:\n- b1\n" > "$tmpdir/k1.yaml"
    insert_bases "$tmpdir/k1.yaml" "b2"
    assertEquals "inserts a second base" "$(echo -e "resources:\n- r1\n\nbases:\n- b2\n- b1\n")" "$(cat "$tmpdir/k1.yaml")"

    echo -e "resources:\n- r1\n" > "$tmpdir/k2.yaml"
    insert_bases "$tmpdir/k2.yaml" "b2"
    assertEquals "inserts the first base" "$(echo -e "resources:\n- r1\n\nbases:\n- b2\n")" "$(cat "$tmpdir/k2.yaml")"
}

function test_insert_bases_kubectl_121() {
    local tmpdir=
    tmpdir="$(mktemp -d)"

    kubectl(){
        echo "Client Version: v1.21.0"
    }

    echo -e "resources:\n- r1\n\n" > "$tmpdir/k1.yaml"
    insert_bases "$tmpdir/k1.yaml" "b2"
    assertEquals "inserts a second base" "$(echo -e "resources:\n- b2\n- r1\n")" "$(cat "$tmpdir/k1.yaml")"

    touch "$tmpdir/k2.yaml"
    insert_bases "$tmpdir/k2.yaml" "b2"
    assertEquals "inserts the first base" "$(echo -e "resources:\n- b2\n")" "$(cat "$tmpdir/k2.yaml")"
}

function test_insert_bases_no_kubectl() {
    local tmpdir=
    tmpdir="$(mktemp -d)"

    commandExists(){
        return 1
    }
    # shellcheck disable=SC2034
    local KUBERNETES_VERSION="1.21.0"

    echo -e "resources:\n- r1\n\n" > "$tmpdir/k1.yaml"
    insert_bases "$tmpdir/k1.yaml" "b2"
    assertEquals "inserts a second base" "$(echo -e "resources:\n- b2\n- r1\n")" "$(cat "$tmpdir/k1.yaml")"

    touch "$tmpdir/k2.yaml"
    insert_bases "$tmpdir/k2.yaml" "b2"
    assertEquals "inserts the first base" "$(echo -e "resources:\n- b2\n")" "$(cat "$tmpdir/k2.yaml")"
}

function test_yaml_indent() {
  assertEquals "$(echo -e "   blah1\n   blah2\n     \"blah3\"")" "$(echo -e "blah1\nblah2\n  \"blah3\"" | yaml_indent "   ")"
}

function test_yaml_newline_to_literal() {
  assertNotEquals 'blah1\nblah2\n  "blah3"' "$(echo -e "blah1\nblah2\n  \"blah3\"")"
  assertEquals 'blah1\nblah2\n  "blah3"' "$(echo -e "blah1\nblah2\n  \"blah3\"" | yaml_newline_to_literal)"
}

function test_yaml_escape_string_quotes() {
  # shellcheck disable=SC2028
  assertEquals 'blah1\nblah2\n  \"blah3\"' "$(echo "blah1\nblah2\n  \"blah3\"" | yaml_escape_string_quotes)"
}

# shellcheck disable=SC1091
. shunit2
