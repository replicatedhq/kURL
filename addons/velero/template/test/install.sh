#!/bin/bash

. ./scripts/common/common.sh
. ./addons/velero/template/base/install.tmpl.sh

# velero_should_wait_for_node_agent_daemonset gates the sc-139656 node-agent wait: it must
# only run when restic/node-agent is enabled, Velero is using the Local Volume Provider
# (Internal Storage, Host Path, or NFS), and the node-agent daemonset actually exists.
#
# kubectl is mocked per test to answer by resource kind so velero_using_local_volume_provider
# (which reads the default BackupStorageLocation and the velero-internal-snapshots PVC) can
# be exercised precisely instead of via a blanket always-succeeds stub.

function test_velero_should_wait_for_node_agent_daemonset_internal_storage() {
    local VELERO_NAMESPACE="velero"
    # shellcheck disable=SC2034
    local VELERO_DISABLE_RESTIC=""
    kubectl() {
        case "$*" in
            *"backupstoragelocation default"*)
                return 1
                ;;
            *"pvc velero-internal-snapshots"*)
                return 0
                ;;
            *"daemonset node-agent"*)
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    }
    assertEquals "waits when restic enabled and using the Internal Storage (PVC-backed) destination" "0" \
        "$(velero_should_wait_for_node_agent_daemonset >/dev/null; echo $?)"
}

function test_velero_should_wait_for_node_agent_daemonset_host_path() {
    local VELERO_NAMESPACE="velero"
    # shellcheck disable=SC2034
    local VELERO_DISABLE_RESTIC=""
    kubectl() {
        case "$*" in
            *"get backupstoragelocation default -o jsonpath"*)
                echo "replicated.com/hostpath"
                return 0
                ;;
            *"backupstoragelocation default"*)
                return 0
                ;;
            *"pvc velero-internal-snapshots"*)
                return 1
                ;;
            *"daemonset node-agent"*)
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    }
    assertEquals "waits when restic enabled and using the Host Path destination (sc-139656)" "0" \
        "$(velero_should_wait_for_node_agent_daemonset >/dev/null; echo $?)"
}

function test_velero_should_wait_for_node_agent_daemonset_nfs() {
    local VELERO_NAMESPACE="velero"
    # shellcheck disable=SC2034
    local VELERO_DISABLE_RESTIC=""
    kubectl() {
        case "$*" in
            *"get backupstoragelocation default -o jsonpath"*)
                echo "replicated.com/nfs"
                return 0
                ;;
            *"backupstoragelocation default"*)
                return 0
                ;;
            *"pvc velero-internal-snapshots"*)
                return 1
                ;;
            *"daemonset node-agent"*)
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    }
    assertEquals "waits when restic enabled and using the NFS destination (sc-139656)" "0" \
        "$(velero_should_wait_for_node_agent_daemonset >/dev/null; echo $?)"
}

function test_velero_should_wait_for_node_agent_daemonset_restic_disabled() {
    local VELERO_NAMESPACE="velero"
    # shellcheck disable=SC2034
    local VELERO_DISABLE_RESTIC="1"
    kubectl() {
        return 0
    }
    assertEquals "does not wait when restic/node-agent is disabled" "1" \
        "$(velero_should_wait_for_node_agent_daemonset >/dev/null; echo $?)"
}

function test_velero_should_wait_for_node_agent_daemonset_not_using_local_volume_provider() {
    local VELERO_NAMESPACE="velero"
    # shellcheck disable=SC2034
    local VELERO_DISABLE_RESTIC=""
    kubectl() {
        case "$*" in
            *"get backupstoragelocation default -o jsonpath"*)
                echo "aws"
                return 0
                ;;
            *"backupstoragelocation default"*)
                return 0
                ;;
            *"pvc velero-internal-snapshots"*)
                return 1
                ;;
            *"daemonset node-agent"*)
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    }
    assertEquals "does not wait for a default (non-LVP, object store) velero install" "1" \
        "$(velero_should_wait_for_node_agent_daemonset >/dev/null; echo $?)"
}

function test_velero_should_wait_for_node_agent_daemonset_no_daemonset() {
    local VELERO_NAMESPACE="velero"
    # shellcheck disable=SC2034
    local VELERO_DISABLE_RESTIC=""
    kubectl() {
        case "$*" in
            *"backupstoragelocation default"*)
                return 1
                ;;
            *"pvc velero-internal-snapshots"*)
                return 0
                ;;
            *"daemonset node-agent"*)
                return 1
                ;;
            *)
                return 1
                ;;
        esac
    }
    assertEquals "does not wait when the node-agent daemonset does not exist" "1" \
        "$(velero_should_wait_for_node_agent_daemonset >/dev/null; echo $?)"
}

. shunit2
