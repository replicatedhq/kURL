#!/bin/bash
# shellcheck disable=SC2034,SC2329 # main() is eval'd as text below, so shellcheck can't see
# that K8S_DISTRO and the stub functions in this file are used by it.

# Regression test for sc-140018: containerd_ensure_pause_image_pinned must run before any
# kubeadm node init/upgrade step has a chance to reschedule pods against an as-yet-unpinned
# pause image. Mirrors scripts/upgrade-test.sh, which covers the equivalent wiring in
# scripts/upgrade.sh.
#
# scripts/install.sh is a top-level entrypoint that executes main() unconditionally at the
# bottom of the file, so it cannot be sourced directly in a test. Extract just the main()
# function body instead and eval it here with every function it calls stubbed out.
#
# No top-level `set -e`: shunit2's assertTrue/assertEquals run `[ ... ]` conditions
# directly, and errexit at this level turns a failing assertion into an opaque
# "unknown failure" instead of the real assertion message.

K8S_DISTRO=kubeadm

MAIN_SRC="$(sed -n '/^function main() {/,/^}/p' ./scripts/install.sh)"
if [ -z "$MAIN_SRC" ]; then
    echo "FAIL: could not extract main() from scripts/install.sh"
    exit 1
fi
eval "$MAIN_SRC"

function test_pins_pause_image_before_configure_no_proxy_and_after_pause_image_upgrade() {
    local result rc

    # Run main() under set -e, matching how scripts/install.sh itself runs it in production.
    # main's own stdout is noise from the stubbed-out helpers, but its stderr is left to flow
    # through to the real stderr instead of being discarded, so a genuine failure is visible
    # in test output rather than looking like a silent, misleading success.
    result="$( set -e
        CALLS=""
        function record() { CALLS="$CALLS $1"; }
        function require_root_user() { record require_root_user; }
        function path_add() { record path_add; }
        function kubernetes_init_hostname() { record kubernetes_init_hostname; }
        function get_patch_yaml() { record get_patch_yaml; }
        function maybe_read_kurl_config_from_cluster() { record maybe_read_kurl_config_from_cluster; }
        function pushd_install_directory() { record pushd_install_directory; }
        function yaml_airgap() { record yaml_airgap; }
        function proxy_bootstrap() { record proxy_bootstrap; }
        function download_util_binaries() { record download_util_binaries; }
        function get_machine_id() { record get_machine_id; }
        function merge_yaml_specs() { record merge_yaml_specs; }
        function apply_bash_flag_overrides() { record apply_bash_flag_overrides; }
        function parse_yaml_into_bash_variables() { record parse_yaml_into_bash_variables; }
        function prompt_license() { record prompt_license; }
        function is_ha() { record is_ha; }
        function parse_kubernetes_target_version() { record parse_kubernetes_target_version; }
        function discover() { record discover; }
        function report_install_start() { record report_install_start; }
        function setup_remote_commands_dirs() { record setup_remote_commands_dirs; }
        function preflights() { record preflights; }
        function init_preflights() { record init_preflights; }
        function kubernetes_upgrade_preflight() { record kubernetes_upgrade_preflight; }
        function common_prompts() { record common_prompts; }
        function journald_persistent() { record journald_persistent; }
        function configure_proxy() { record configure_proxy; }
        function configure_no_proxy_preinstall() { record configure_no_proxy_preinstall; }
        function kubeadm_addon_for_each() { record "kubeadm_addon_for_each:$1"; }
        function kubernetes_get_packages() { record kubernetes_get_packages; }
        function preflights_require_host_packages() { record preflights_require_host_packages; }
        function install_host_dependencies() { record install_host_dependencies; }
        function host_preflights() { record host_preflights; }
        function cluster_preflights() { record cluster_preflights; }
        function get_common() { record get_common; }
        function setup_kubeadm_kustomize() { record setup_kubeadm_kustomize; }
        function rook_upgrade_maybe_report_upgrade_rook() { record rook_upgrade_maybe_report_upgrade_rook; }
        function kubernetes_pre_init() { record kubernetes_pre_init; }
        function discover_pod_subnet() { record discover_pod_subnet; }
        function discover_service_subnet() { record discover_service_subnet; }
        function configure_no_proxy() { record configure_no_proxy; }
        function install_cri() { record install_cri; }
        function kubernetes_configure_pause_image_upgrade() { record kubernetes_configure_pause_image_upgrade; }
        function containerd_ensure_pause_image_pinned() { record containerd_ensure_pause_image_pinned; }
        function get_shared() { record get_shared; }
        function report_upgrade_kubernetes() { record report_upgrade_kubernetes; }
        function report_kubernetes_install() { record report_kubernetes_install; }
        function kurl_init_config() { record kurl_init_config; }
        function maybe_set_kurl_cluster_uuid() { record maybe_set_kurl_cluster_uuid; }
        function kurl_install_support_bundle_configmap() { record kurl_install_support_bundle_configmap; }
        function maybe_cleanup_rook() { record maybe_cleanup_rook; }
        function maybe_cleanup_longhorn() { record maybe_cleanup_longhorn; }
        function helmfile_sync() { record helmfile_sync; }
        function kubeadm_post_init() { record kubeadm_post_init; }
        function uninstall_docker() { record uninstall_docker; }
        function check_proxy_config() { record check_proxy_config; }
        function rook_maybe_migrate_from_openebs() { record rook_maybe_migrate_from_openebs; }
        function outro() { record outro; }
        function package_cleanup() { record package_cleanup; }
        function popd_install_directory() { record popd_install_directory; }
        function report_install_success() { record report_install_success; }
        function logStep() { :; }

        main >/dev/null
        echo "$CALLS"
    )"
    rc=$?

    assertEquals "main() exits zero (a stubbed function may be missing or misbehaving; see stderr above for details)" 0 "$rc"
    if [ "$rc" -ne 0 ]; then
        return
    fi
    echo "$result"

    local pos_install_cri pos_pin pos_configure pos_no_proxy
    pos_install_cri="$(echo "$result" | tr ' ' '\n' | grep -n -x "install_cri" | cut -d: -f1)"
    pos_configure="$(echo "$result" | tr ' ' '\n' | grep -n -x "kubernetes_configure_pause_image_upgrade" | cut -d: -f1)"
    pos_pin="$(echo "$result" | tr ' ' '\n' | grep -n -x "containerd_ensure_pause_image_pinned" | cut -d: -f1)"
    pos_no_proxy="$(echo "$result" | tr ' ' '\n' | grep -n -x "configure_no_proxy" | cut -d: -f1)"

    assertTrue "containerd_ensure_pause_image_pinned runs after install_cri" \
        '[ "$pos_install_cri" -lt "$pos_pin" ]'

    assertTrue "containerd_ensure_pause_image_pinned runs after kubernetes_configure_pause_image_upgrade" \
        '[ "$pos_configure" -lt "$pos_pin" ]'

    assertTrue "containerd_ensure_pause_image_pinned runs after configure_no_proxy (install_cri's prerequisite), so the pin check always has a running containerd to query" \
        '[ "$pos_no_proxy" -lt "$pos_pin" ]'
}

# shellcheck disable=SC1091
. shunit2
