#!/bin/bash
# shellcheck disable=SC2034,SC2329 # main() is eval'd as text below, so shellcheck can't see
# that K8S_DISTRO and the stub functions in this file are used by it.

set -e

# Regression test for sc-140018: containerd_ensure_pause_image_pinned must run before the
# kubeadm node upgrade (inside maybe_upgrade) has a chance to restart the kubelet and
# reschedule pods against the new, as-yet-unpinned pause image. Pinning only after
# maybe_upgrade leaves that image exposed to kubelet GC for the whole node upgrade.
#
# scripts/upgrade.sh is a top-level entrypoint that executes main() unconditionally at the
# bottom of the file, so it cannot be sourced directly in a test. Extract just the main()
# function body instead and eval it here with every function it calls stubbed out.

K8S_DISTRO=kubeadm

MAIN_SRC="$(sed -n '/^function main() {/,/^}/p' ./scripts/upgrade.sh)"
if [ -z "$MAIN_SRC" ]; then
    echo "FAIL: could not extract main() from scripts/upgrade.sh"
    exit 1
fi
eval "$MAIN_SRC"

FAILURES=0
function assertEquals() {
    local msg="$1" expected="$2" actual="$3"
    if [ "$expected" != "$actual" ]; then
        echo "FAIL: $msg (expected [$expected], got [$actual])"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $msg"
    fi
}

function test_pins_pause_image_before_kubeadm_node_upgrade() {
    local result
    result="$( (
        CALLS=""
        function record() { CALLS="$CALLS $1"; }
        function require_root_user() { record require_root_user; }
        function path_add() { record path_add; }
        function kubernetes_init_hostname() { record kubernetes_init_hostname; }
        function get_patch_yaml() { record get_patch_yaml; }
        function maybe_read_kurl_config_from_cluster() { record maybe_read_kurl_config_from_cluster; }
        function move_airgap_assets() { record move_airgap_assets; }
        function pushd_install_directory() { record pushd_install_directory; }
        function proxy_bootstrap() { record proxy_bootstrap; }
        function download_util_binaries() { record download_util_binaries; }
        function get_machine_id() { record get_machine_id; }
        function merge_yaml_specs() { record merge_yaml_specs; }
        function apply_bash_flag_overrides() { record apply_bash_flag_overrides; }
        function parse_yaml_into_bash_variables() { record parse_yaml_into_bash_variables; }
        function parse_kubernetes_target_version() { record parse_kubernetes_target_version; }
        function discover() { record discover; }
        function preflights() { record preflights; }
        function journald_persistent() { record journald_persistent; }
        function configure_proxy() { record configure_proxy; }
        function configure_no_proxy() { record configure_no_proxy; }
        function kubeadm_addon_for_each() { record "kubeadm_addon_for_each:$1"; }
        function kubernetes_get_packages() { record kubernetes_get_packages; }
        function kubernetes_maybe_get_packages_airgap() { record kubernetes_maybe_get_packages_airgap; }
        function preflights_require_host_packages() { record preflights_require_host_packages; }
        function host_preflights() { record host_preflights; }
        function install_host_dependencies() { record install_host_dependencies; }
        function get_common() { record get_common; }
        function setup_kubeadm_kustomize() { record setup_kubeadm_kustomize; }
        function install_cri() { record install_cri; }
        function get_shared() { record get_shared; }
        function kubernetes_pre_init() { record kubernetes_pre_init; }
        function maybe_upgrade() { record maybe_upgrade; }
        function kubernetes_configure_pause_image_upgrade() { record kubernetes_configure_pause_image_upgrade; }
        function containerd_ensure_pause_image_pinned() { record containerd_ensure_pause_image_pinned; }
        function install_helm() { record install_helm; }
        function uninstall_docker() { record uninstall_docker; }
        function outro() { record outro; }
        function package_cleanup() { record package_cleanup; }
        function popd_install_directory() { record popd_install_directory; }
        function logStep() { :; }

        main >/dev/null 2>&1

        echo "$CALLS"
    ) )"
    echo "$result"

    local pos_install_cri pos_pin pos_configure pos_maybe_upgrade
    pos_install_cri="$(echo "$result" | tr ' ' '\n' | grep -n -x "install_cri" | cut -d: -f1)"
    pos_configure="$(echo "$result" | tr ' ' '\n' | grep -n -x "kubernetes_configure_pause_image_upgrade" | cut -d: -f1)"
    pos_pin="$(echo "$result" | tr ' ' '\n' | grep -n -x "containerd_ensure_pause_image_pinned" | cut -d: -f1)"
    pos_maybe_upgrade="$(echo "$result" | tr ' ' '\n' | grep -n -x "maybe_upgrade" | cut -d: -f1)"

    [ "$pos_install_cri" -lt "$pos_pin" ]
    assertEquals "containerd_ensure_pause_image_pinned runs after install_cri" "0" "$?"

    [ "$pos_configure" -lt "$pos_pin" ]
    assertEquals "containerd_ensure_pause_image_pinned runs after kubernetes_configure_pause_image_upgrade" "0" "$?"

    [ "$pos_pin" -lt "$pos_maybe_upgrade" ]
    assertEquals "containerd_ensure_pause_image_pinned runs before maybe_upgrade (the kubeadm node upgrade), so the pin happens before kubelet can reschedule pods against the new image" "0" "$?"
}

test_pins_pause_image_before_kubeadm_node_upgrade

if [ "$FAILURES" -gt 0 ]; then
    echo "$FAILURES upgrade.sh test(s) failed."
    exit 1
fi
echo "All upgrade.sh tests passed."
