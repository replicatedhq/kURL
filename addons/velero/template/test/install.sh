#!/bin/bash

. ./scripts/common/common.sh
. ./addons/velero/template/base/install.tmpl.sh

# velero_should_wait_for_node_agent_daemonset gates the sc-139656 node-agent wait: it must
# only run when restic/node-agent is enabled, Velero is using the Internal Storage
# (PVC-backed) snapshot destination, and the node-agent daemonset actually exists.

function test_velero_should_wait_for_node_agent_daemonset_all_conditions_met() {
    local VELERO_NAMESPACE="velero"
    # shellcheck disable=SC2034
    local VELERO_DISABLE_RESTIC=""
    kubectl() {
        echo "True"
    }
    assertEquals "waits when restic enabled, using internal pvc snapshots, and node-agent exists" "0" \
        "$(velero_should_wait_for_node_agent_daemonset "1" >/dev/null; echo $?)"
}

function test_velero_should_wait_for_node_agent_daemonset_restic_disabled() {
    local VELERO_NAMESPACE="velero"
    # shellcheck disable=SC2034
    local VELERO_DISABLE_RESTIC="1"
    kubectl() {
        echo "True"
    }
    assertEquals "does not wait when restic/node-agent is disabled" "1" \
        "$(velero_should_wait_for_node_agent_daemonset "1" >/dev/null; echo $?)"
}

function test_velero_should_wait_for_node_agent_daemonset_not_using_internal_pvc_snapshots() {
    local VELERO_NAMESPACE="velero"
    # shellcheck disable=SC2034
    local VELERO_DISABLE_RESTIC=""
    kubectl() {
        echo "True"
    }
    assertEquals "does not wait for a default (non-LVP) velero install" "1" \
        "$(velero_should_wait_for_node_agent_daemonset "0" >/dev/null; echo $?)"
}

function test_velero_should_wait_for_node_agent_daemonset_no_daemonset() {
    # shellcheck disable=SC2034
    local VELERO_NAMESPACE="velero"
    # shellcheck disable=SC2034
    local VELERO_DISABLE_RESTIC=""
    kubectl() {
        return 1
    }
    assertEquals "does not wait when the node-agent daemonset does not exist" "1" \
        "$(velero_should_wait_for_node_agent_daemonset "1" >/dev/null; echo $?)"
}

. shunit2
