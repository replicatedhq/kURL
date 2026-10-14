#!/bin/bash
# shellcheck disable=SC2034 # these locals are read inside single-quoted assertTrue
# expressions below, which shellcheck can't see into.

# Regression test for sc-140018: containerd_ensure_pause_image_pinned must run right after
# install_cri (and the kubelet pause-image flag update kubernetes_configure_pause_image_upgrade
# makes alongside it), before any kubeadm init/upgrade step has a chance to reschedule pods
# against an as-yet-unpinned pause image. Mirrors scripts/upgrade-test.sh, which covers the
# equivalent wiring in scripts/upgrade.sh.
#
# scripts/install.sh is a top-level entrypoint that executes main() unconditionally at the
# bottom of the file, so it cannot be sourced directly in a test. This asserts call order
# statically against the extracted main() source instead of stubbing and running every function
# it calls -- stubbing the full call graph means any unrelated future change to main() breaks
# this test with an unrelated "command not found".

MAIN_SRC="$(sed -n '/^function main() {/,/^}/p' ./scripts/install.sh)"
if [ -z "$MAIN_SRC" ]; then
    echo "FAIL: could not extract main() from scripts/install.sh"
    exit 1
fi

function test_pins_pause_image_after_install_cri_and_pause_image_upgrade() {
    local install_cri_line configure_line pin_line

    install_cri_line="$(echo "$MAIN_SRC" | grep -n -x '    install_cri' | cut -d: -f1)"
    configure_line="$(echo "$MAIN_SRC" | grep -n -x '    kubernetes_configure_pause_image_upgrade' | cut -d: -f1)"
    pin_line="$(echo "$MAIN_SRC" | grep -n -x '    containerd_ensure_pause_image_pinned' | cut -d: -f1)"

    assertTrue "install_cri, kubernetes_configure_pause_image_upgrade and containerd_ensure_pause_image_pinned must each appear exactly once" \
        '[ -n "$install_cri_line" ] && [ -n "$configure_line" ] && [ -n "$pin_line" ]'

    assertTrue "containerd_ensure_pause_image_pinned runs after install_cri" \
        '[ -n "$install_cri_line" ] && [ -n "$pin_line" ] && [ "$install_cri_line" -lt "$pin_line" ]'

    assertTrue "containerd_ensure_pause_image_pinned runs after kubernetes_configure_pause_image_upgrade" \
        '[ -n "$configure_line" ] && [ -n "$pin_line" ] && [ "$configure_line" -lt "$pin_line" ]'
}

# shellcheck disable=SC1091
. shunit2
