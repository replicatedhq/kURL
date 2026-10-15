#!/bin/bash

set -e

# shellcheck disable=SC1091
. ./scripts/common/common.sh
# shellcheck disable=SC1091
. ./scripts/common/kubernetes.sh
# shellcheck disable=SC1091
. ./scripts/common/upgrade.sh

# kubernetes_install_host_packages already restarts kubelet itself (safely, via
# kubernetes_restart_kubelet, quiescing control plane static pods first when they
# are present). An immediate, un-quiesced "systemctl restart kubelet" right after
# it returns races the just-recreated static pod containers against a second set
# of freshly (re)created ones, reproducing the exact port-bind/churn race #6181's
# quiesce logic exists to avoid - just on the second restart instead of the first.
function test_upgrade_kubernetes_local_master_does_not_double_restart_kubelet() {
    local calls=""

    get_local_node_name() {
        #shellcheck disable=SC2317
        echo "node1"
    }
    kubectl() {
        #shellcheck disable=SC2317
        if [ "$1" = "get" ] && [ "$2" = "node" ]; then
            echo "node1 Ready control-plane 1d v1.36.5"
        fi
    }
    discover_local_kubernetes_version() {
        #shellcheck disable=SC2317
        echo "1.36.5"
    }
    kubernetes_load_images() { :; }
    upgrade_kubeadm() { :; }
    kubeadm() { :; }
    confirmY() { :; }
    kubernetes_drain() { :; }
    maybe_patch_node_cri_socket_annotation() { :; }
    spinner_kubernetes_api_stable() { :; }
    kubernetes_apply_image_overrides() { :; }
    upgrade_etcd_image_18() { :; }
    upgrade_should_remove_container_runtime_flag() { :; }
    kubernetes_install_host_packages() {
        #shellcheck disable=SC2317
        calls="$calls kubernetes_install_host_packages"
    }
    systemctl() {
        #shellcheck disable=SC2317
        calls="$calls systemctl:$*"
    }
    upgrade_delete_node_flannel() { :; }
    spinner_until() { :; }
    kubernetes_node_has_version() { :; }
    kubernetes_all_nodes_ready() { :; }
    rm() { :; }

    upgrade_kubernetes_local_master "1.37.1"

    # kubernetes_install_host_packages is mocked above and does not itself emit a
    # "systemctl:restart kubelet" call here, so any occurrence in $calls can only
    # come from upgrade_kubernetes_local_master calling systemctl directly itself
    # - the redundant restart this test guards against.
    case "$calls" in
        *"systemctl:restart kubelet"*)
            fail "upgrade_kubernetes_local_master should not restart kubelet itself; kubernetes_install_host_packages already does so safely: $calls"
            ;;
    esac

    unset -f get_local_node_name kubectl discover_local_kubernetes_version \
        kubernetes_load_images upgrade_kubeadm kubeadm confirmY kubernetes_drain \
        maybe_patch_node_cri_socket_annotation spinner_kubernetes_api_stable \
        kubernetes_apply_image_overrides upgrade_etcd_image_18 \
        upgrade_should_remove_container_runtime_flag kubernetes_install_host_packages \
        systemctl upgrade_delete_node_flannel spinner_until kubernetes_node_has_version \
        kubernetes_all_nodes_ready rm
}

# shellcheck disable=SC1091
. shunit2
