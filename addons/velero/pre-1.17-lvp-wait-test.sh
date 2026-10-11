#!/bin/bash

. ./scripts/common/common.sh

# Guards the sc-139656 node-agent settle wait across every live, LVP-capable Velero
# version that predates 1.17 (the first version whose install.sh consumes the shared
# template directly). Each of these versions ships its own hand-duplicated copy of
# velero_should_wait_for_node_agent_daemonset / velero_bsl_provider /
# velero_bsl_is_local_volume_provider / velero_using_local_volume_provider, so this
# exercises each version's own install.sh directly rather than the shared template
# (which only 1.17+ consume) to catch a version whose copy diverges or regresses
# independently of the others.
#
# kubectl is mocked per test to answer by resource kind, same approach as
# addons/velero/template/test/install.sh.

PRE_1_17_LVP_VERSIONS="1.10.1 1.10.2 1.11.0 1.11.1 1.12.0 1.12.1 1.12.2 1.12.3 1.13.1 1.13.2 1.14.0 1.15.2 1.16.2"

function pre_1_17_lvp_wait_source_version() {
    local version="$1"
    # shellcheck disable=SC1090
    . "./addons/velero/${version}/install.sh"
}

function test_velero_should_wait_for_node_agent_daemonset_internal_storage() {
    local version
    for version in $PRE_1_17_LVP_VERSIONS; do
        pre_1_17_lvp_wait_source_version "$version"

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
        assertEquals "$version: waits when restic enabled and using the Internal Storage (PVC-backed) destination" "0" \
            "$(velero_should_wait_for_node_agent_daemonset >/dev/null; echo $?)"
    done
}

function test_velero_should_wait_for_node_agent_daemonset_host_path() {
    local version
    for version in $PRE_1_17_LVP_VERSIONS; do
        pre_1_17_lvp_wait_source_version "$version"

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
        assertEquals "$version: waits when restic enabled and using the Host Path destination (sc-139656)" "0" \
            "$(velero_should_wait_for_node_agent_daemonset >/dev/null; echo $?)"
    done
}

function test_velero_should_wait_for_node_agent_daemonset_nfs() {
    local version
    for version in $PRE_1_17_LVP_VERSIONS; do
        pre_1_17_lvp_wait_source_version "$version"

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
        assertEquals "$version: waits when restic enabled and using the NFS destination (sc-139656)" "0" \
            "$(velero_should_wait_for_node_agent_daemonset >/dev/null; echo $?)"
    done
}

function test_velero_should_wait_for_node_agent_daemonset_restic_disabled() {
    local version
    for version in $PRE_1_17_LVP_VERSIONS; do
        pre_1_17_lvp_wait_source_version "$version"

        local VELERO_NAMESPACE="velero"
        # shellcheck disable=SC2034
        local VELERO_DISABLE_RESTIC="1"
        kubectl() {
            return 0
        }
        assertEquals "$version: does not wait when restic/node-agent is disabled" "1" \
            "$(velero_should_wait_for_node_agent_daemonset >/dev/null; echo $?)"
    done
}

function test_velero_should_wait_for_node_agent_daemonset_not_using_local_volume_provider() {
    local version
    for version in $PRE_1_17_LVP_VERSIONS; do
        pre_1_17_lvp_wait_source_version "$version"

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
        assertEquals "$version: does not wait for a default (non-LVP, object store) velero install" "1" \
            "$(velero_should_wait_for_node_agent_daemonset >/dev/null; echo $?)"
    done
}

function test_velero_should_wait_for_node_agent_daemonset_no_daemonset() {
    local version
    for version in $PRE_1_17_LVP_VERSIONS; do
        pre_1_17_lvp_wait_source_version "$version"

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
        assertEquals "$version: does not wait when the node-agent daemonset does not exist" "1" \
            "$(velero_should_wait_for_node_agent_daemonset >/dev/null; echo $?)"
    done
}

. shunit2
