#!/bin/bash
# shellcheck disable=SC2034 # these locals are read inside single-quoted assertTrue
# expressions below, which shellcheck can't see into.

# Regression test for sc-140018: containerd_ensure_pause_image_pinned must run both before and
# after the kubeadm node upgrade (maybe_upgrade). The first call pins a pause image that
# install_cri already imported while restarting containerd with the new sandbox_image. The
# second call (after kubernetes_configure_pause_image_upgrade, which itself must stay after
# maybe_upgrade so kubeadm can't clobber its kubelet flag rewrite) catches a pause image that is
# instead first imported by kubernetes_load_images during maybe_upgrade itself, where
# CONTAINERD_NEEDS_RESTART is usually 0 and the old daemon never restarts to trigger the pin.
#
# scripts/upgrade.sh is a top-level entrypoint that executes main() unconditionally at the
# bottom of the file, so it cannot be sourced directly in a test. This asserts call order
# statically against the extracted main() source instead of stubbing and running every function
# it calls -- stubbing the full call graph means any unrelated future change to main() breaks
# this test with an unrelated "command not found".

MAIN_SRC="$(sed -n '/^function main() {/,/^}/p' ./scripts/upgrade.sh)"
if [ -z "$MAIN_SRC" ]; then
    echo "FAIL: could not extract main() from scripts/upgrade.sh"
    exit 1
fi

function test_pins_pause_image_before_and_after_the_kubeadm_node_upgrade() {
    local pin_lines first_pin_line last_pin_line configure_line upgrade_line pin_count

    pin_lines="$(echo "$MAIN_SRC" | grep -n -x '    containerd_ensure_pause_image_pinned' | cut -d: -f1)"
    configure_line="$(echo "$MAIN_SRC" | grep -n -x '    kubernetes_configure_pause_image_upgrade' | cut -d: -f1)"
    upgrade_line="$(echo "$MAIN_SRC" | grep -n -x '    maybe_upgrade' | cut -d: -f1)"
    first_pin_line="$(echo "$pin_lines" | head -n1)"
    last_pin_line="$(echo "$pin_lines" | tail -n1)"
    pin_count="$(echo "$pin_lines" | grep -c .)"

    assertEquals "containerd_ensure_pause_image_pinned must be called exactly twice" 2 "$pin_count"
    assertTrue "maybe_upgrade must be present exactly once" '[ -n "$upgrade_line" ]'
    assertTrue "kubernetes_configure_pause_image_upgrade must be present exactly once" '[ -n "$configure_line" ]'

    assertTrue "the first containerd_ensure_pause_image_pinned call must run before maybe_upgrade (the kubeadm node upgrade), so a pause image already imported by install_cri is pinned before kubelet can reschedule pods against it" \
        '[ -n "$first_pin_line" ] && [ -n "$upgrade_line" ] && [ "$first_pin_line" -lt "$upgrade_line" ]'

    assertTrue "kubernetes_configure_pause_image_upgrade must run after maybe_upgrade: kubeadm upgrade node can rewrite kubeadm-flags.env, so the kubelet pause-image flag rewrite has to happen after, or kubeadm could clobber it" \
        '[ -n "$configure_line" ] && [ -n "$upgrade_line" ] && [ "$upgrade_line" -lt "$configure_line" ]'

    assertTrue "the second containerd_ensure_pause_image_pinned call must run after kubernetes_configure_pause_image_upgrade, so a pause image only imported during maybe_upgrade (via kubernetes_load_images) still gets pinned on this run" \
        '[ -n "$last_pin_line" ] && [ -n "$configure_line" ] && [ "$configure_line" -lt "$last_pin_line" ]'
}

# shellcheck disable=SC1091
. shunit2
