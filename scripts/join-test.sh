#!/bin/bash
# shellcheck disable=SC2034 # these locals are read inside single-quoted assertTrue
# expressions below, which shellcheck can't see into.

# Regression test for sc-140018: a joined node runs install_cri too, importing the pause
# image while whichever containerd daemon generation is running at the time may still have
# the old sandbox_image -- containerd_ensure_pause_image_pinned must run there as well, or
# joined nodes stay unpinned until someone later runs install.sh or upgrade.sh on them. On an
# airgapped cluster those are exactly the nodes that can't re-pull the pause image after GC.
#
# scripts/join.sh is a top-level entrypoint that executes main() unconditionally at the
# bottom of the file, so it cannot be sourced directly in a test. This asserts call order
# statically against the extracted main() source instead of stubbing and running every function
# it calls -- stubbing the full call graph means any unrelated future change to main() breaks
# this test with an unrelated "command not found".

MAIN_SRC="$(sed -n '/^function main() {/,/^}/p' ./scripts/join.sh)"
if [ -z "$MAIN_SRC" ]; then
    echo "FAIL: could not extract main() from scripts/join.sh"
    exit 1
fi

function test_pins_pause_image_after_install_cri() {
    local install_cri_line pin_line

    install_cri_line="$(echo "$MAIN_SRC" | grep -n -x '    install_cri' | cut -d: -f1)"
    pin_line="$(echo "$MAIN_SRC" | grep -n -x '    containerd_ensure_pause_image_pinned' | cut -d: -f1)"

    assertTrue "install_cri and containerd_ensure_pause_image_pinned must each appear exactly once" \
        '[ -n "$install_cri_line" ] && [ -n "$pin_line" ]'

    assertTrue "containerd_ensure_pause_image_pinned runs after install_cri" \
        '[ -n "$install_cri_line" ] && [ -n "$pin_line" ] && [ "$install_cri_line" -lt "$pin_line" ]'
}

function test_pins_pause_image_after_join_imports_it() {
    local join_line pin_line

    # join() performs the actual `kubeadm join`, which is what imports the pause image into
    # containerd on a joined node. Pinning any earlier (e.g. right after install_cri) is a
    # no-op: the image isn't in containerd yet, so the joined node ends up permanently
    # unpinned until a later install.sh/upgrade.sh run touches it.
    join_line="$(echo "$MAIN_SRC" | grep -n -x '    join' | cut -d: -f1)"
    pin_line="$(echo "$MAIN_SRC" | grep -n -x '    containerd_ensure_pause_image_pinned' | cut -d: -f1)"

    assertTrue "join and containerd_ensure_pause_image_pinned must each appear exactly once" \
        '[ -n "$join_line" ] && [ -n "$pin_line" ]'

    assertTrue "containerd_ensure_pause_image_pinned runs after join, which performs kubeadm join and actually imports the pause image" \
        '[ -n "$join_line" ] && [ -n "$pin_line" ] && [ "$join_line" -lt "$pin_line" ]'
}

# shellcheck disable=SC1091
. shunit2
