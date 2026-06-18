#!/bin/bash
# Containerd configure/upgrade regression tests.
#
# MUST run inside a disposable container (it writes to the real /etc/containerd):
#   docker run --rm -v "$(pwd)":/src -w /src ubuntu:24.04 bash ./scripts/common/containerd-test.sh
# or via the Makefile target:
#   make docker-test-containerd
#
# Tests exercise containerd_configure() against checked-in `containerd config default`
# fixtures for containerd 1.7 (config schema v2) and 2.0/2.1 (schema v3), plus the
# cross-major upgrade evaluation logic in scripts/common/containerd.sh.

. ./scripts/common/common.sh
. ./scripts/common/containerd.sh
. ./addons/containerd/template/base/install.sh

# --- stubs: defined AFTER sourcing, same shell, so they shadow the real definitions ---

FIXTURE=
# Dispatches on subcommand. `config dump` simulates containerd's merge: drop-ins are
# only included when config.toml's imports actually references conf.d — so a missing
# imports patch fails the same way it would with a real binary.
function containerd() {
    case "$*" in
        "config default")
            cat "$FIXTURE"
            ;;
        *"config dump"*)
            cat /etc/containerd/config.toml
            if grep -q "imports = \['/etc/containerd/conf.d/\*.toml'\]" /etc/containerd/config.toml; then
                cat /etc/containerd/conf.d/*.toml 2>/dev/null
            fi
            ;;
        *)
            return 0
            ;;
    esac
}
function is_ubuntu_2404() { return "${_IS_UBUNTU_2404:-1}"; }
function containerd_kubernetes_pause_image() { echo "${_PAUSE_IMAGE:-registry.k8s.io/pause:3.10}"; }
function systemctl() { return 1; }      # "not active" → skip ctr pause-image import
function kubernetes_version_minor() { echo "$1" | cut -d. -f2; }
function log() { echo "$*"; }
function logWarn() { echo "WARN: $*"; }

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

function run_configure_with_fixture() {
    FIXTURE="$1"
    rm -rf /etc/containerd
    CONTAINERD_PRESERVE_CONFIG="" CONTAINERD_TOML_CONFIG="" containerd_configure >/dev/null
}

FIXTURE_17=scripts/common/test/testdata/containerd-config-default-1.7.toml
FIXTURE_20=scripts/common/test/testdata/containerd-config-default-2.0.toml
FIXTURE_21=scripts/common/test/testdata/containerd-config-default-2.1.toml

DROPIN=/etc/containerd/conf.d/50-replicated.toml
USER_DROPIN=/etc/containerd/conf.d/99-user.toml

# bin/toml stub for the 1.x leaf-merge path. The real Go tool (kurl_util/cmd/toml) merges the
# patchfile into the basefile; its merge correctness is unit-tested in
# kurl_util/cmd/toml/main_test.go. The 1.x test here only asserts that the user value lands in
# config.toml (not on a drop-in), so a minimal append into the basefile suffices. install.sh
# invokes it by absolute path ("$DIR/bin/toml"), so we point DIR at a temp dir holding the stub.
TOML_STUB_DIR="$(mktemp -d)"
mkdir -p "$TOML_STUB_DIR/bin"
cat > "$TOML_STUB_DIR/bin/toml" <<'STUB'
#!/bin/bash
basefile= patchfile=
for arg in "$@"; do
    case "$arg" in
        -basefile=*) basefile="${arg#-basefile=}" ;;
        -patchfile=*) patchfile="${arg#-patchfile=}" ;;
    esac
done
cat "$patchfile" >> "$basefile"
STUB
chmod +x "$TOML_STUB_DIR/bin/toml"
DIR="$TOML_STUB_DIR"

# --- 1.x tests: assert config.toml (sed approach) ---

function test_systemd_cgroup_1x() {
    run_configure_with_fixture "$FIXTURE_17"
    grep -A2 'io.containerd.grpc.v1.cri".containerd.runtimes.runc.options' /etc/containerd/config.toml \
        | grep -q 'SystemdCgroup = true'
    assertEquals "SystemdCgroup in 1.x grpc table (config.toml)" "0" "$?"
    assertEquals "No conf.d drop-in for 1.x" "" "$(ls /etc/containerd/conf.d/ 2>/dev/null || true)"
}

function test_pause_image_1x() {
    _PAUSE_IMAGE="registry.k8s.io/pause:3.9"
    run_configure_with_fixture "$FIXTURE_17"
    grep -q 'sandbox_image = "registry.k8s.io/pause:3.9"' /etc/containerd/config.toml
    assertEquals "sandbox_image set in config.toml for 1.x" "0" "$?"
    unset _PAUSE_IMAGE
}

function test_config_path_1x() {
    run_configure_with_fixture "$FIXTURE_17"
    grep -q 'config_path = "/etc/containerd/certs.d"' /etc/containerd/config.toml
    assertEquals "config_path set in config.toml for 1.x" "0" "$?"
}

function test_log_level_1x() {
    run_configure_with_fixture "$FIXTURE_17"
    grep -q 'level = "warn"' /etc/containerd/config.toml
    assertEquals "log level warn in config.toml for 1.x" "0" "$?"
}

function test_apparmor_ubuntu2404_1x() {
    _IS_UBUNTU_2404=0
    run_configure_with_fixture "$FIXTURE_17"
    grep -q 'disable_apparmor = true' /etc/containerd/config.toml
    assertEquals "disable_apparmor true in config.toml on Ubuntu 24.04 with 1.x" "0" "$?"
    _IS_UBUNTU_2404=1
}

# --- 2.x tests: assert conf.d/50-replicated.toml (drop-in approach) ---

function test_systemd_cgroup_2x() {
    run_configure_with_fixture "$FIXTURE_20"
    [ -f "$DROPIN" ]
    assertEquals "50-replicated.toml exists for 2.x" "0" "$?"
    grep -A1 "io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options" "$DROPIN" \
        | grep -q 'SystemdCgroup = true'
    assertEquals "SystemdCgroup in drop-in under cri.v1.runtime" "0" "$?"
    local in_config
    in_config="$(grep 'SystemdCgroup' /etc/containerd/config.toml || true)"
    assertEquals "No kURL-written SystemdCgroup in config.toml for 2.x" "" "$in_config"
}

function test_imports_2x() {
    run_configure_with_fixture "$FIXTURE_20"
    # containerd does not load conf.d on its own — config.toml imports must point at it
    grep -q "imports = \['/etc/containerd/conf.d/\*.toml'\]" /etc/containerd/config.toml
    assertEquals "config.toml imports references conf.d for 2.x" "0" "$?"
}

function test_config_path_2x() {
    run_configure_with_fixture "$FIXTURE_20"
    grep -A1 "io.containerd.transfer.v1.local" "$DROPIN" \
        | grep -q "config_path = '/etc/containerd/certs.d'"
    assertEquals "transfer.v1.local config_path in drop-in" "0" "$?"
    grep -A1 "io.containerd.cri.v1.images'.registry" "$DROPIN" \
        | grep -q "config_path = '/etc/containerd/certs.d'"
    assertEquals "cri.v1.images registry config_path in drop-in" "0" "$?"
    ! grep -q 'certs\.d:/etc/docker' "$DROPIN"
    assertEquals "No colon-separated config_path in drop-in" "0" "$?"
}

function test_log_level_2x() {
    run_configure_with_fixture "$FIXTURE_20"
    grep -A1 '^\[debug\]' "$DROPIN" | grep -q 'level = "warn"'
    assertEquals "log level warn in drop-in for 2.x" "0" "$?"
}

function test_apparmor_ubuntu2404_2x() {
    _IS_UBUNTU_2404=0
    run_configure_with_fixture "$FIXTURE_20"
    grep -q 'disable_apparmor = true' "$DROPIN"
    assertEquals "disable_apparmor true in drop-in on Ubuntu 24.04 with 2.x" "0" "$?"
    _IS_UBUNTU_2404=1
}

function test_pause_image_2x() {
    _PAUSE_IMAGE="registry.k8s.io/pause:3.10"
    run_configure_with_fixture "$FIXTURE_20"
    grep -A1 'pinned_images' "$DROPIN" | grep -q "sandbox = 'registry.k8s.io/pause:3.10'"
    assertEquals "pinned sandbox image in drop-in for 2.x" "0" "$?"
    unset _PAUSE_IMAGE
}

function test_idempotent_2x() {
    run_configure_with_fixture "$FIXTURE_20"
    FIXTURE="$FIXTURE_20"
    CONTAINERD_PRESERVE_CONFIG="" CONTAINERD_TOML_CONFIG="" containerd_configure >/dev/null   # second run, no /etc cleanup
    assertEquals "pinned_images appears exactly once after re-run" "1" \
        "$(grep -c 'pinned_images' "$DROPIN")"
}

function test_systemd_cgroup_2_1x() {
    run_configure_with_fixture "$FIXTURE_21"
    grep -A1 "io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options" "$DROPIN" \
        | grep -q 'SystemdCgroup = true'
    assertEquals "SystemdCgroup in drop-in for containerd 2.1" "0" "$?"
    grep -q "imports = \['/etc/containerd/conf.d/\*.toml'\]" /etc/containerd/config.toml
    assertEquals "config.toml imports references conf.d for 2.1" "0" "$?"
}

# --- CONTAINERD_TOML_CONFIG tests ---
#
# NOTE: the `containerd config dump` stub does NOT simulate last-write-wins merge precedence —
# it just cats config.toml + conf.d/*.toml in shell-glob order. So these tests assert file
# PLACEMENT and ordering, not merged scalar precedence. True runtime precedence and TOML
# parse-rejection are verified against real containerd 2.0.5/2.1.0 binaries in the plan's
# Phase 1 step-0 verification and in CI.

function run_configure_with_tomlconfig() {
    FIXTURE="$1"
    local toml="$2"
    rm -rf /etc/containerd
    CONTAINERD_PRESERVE_CONFIG="" CONTAINERD_TOML_CONFIG="$toml" containerd_configure >/dev/null
}

function test_tomlconfig_dropin_2x() {
    local fixture="$1" label="$2"
    run_configure_with_tomlconfig "$fixture" $'[debug]\n  level = "info"'
    [ -f "$USER_DROPIN" ]
    assertEquals "99-user.toml created for $label" "0" "$?"
    grep -q 'level = "info"' "$USER_DROPIN"
    assertEquals "user value present in 99-user.toml for $label" "0" "$?"
    grep -q 'level = "warn"' "$DROPIN"
    assertEquals "kURL default still in 50-replicated.toml for $label" "0" "$?"
    # 2.x must NOT leaf-merge the user value into the base config.toml
    ! grep -q 'level = "info"' /etc/containerd/config.toml
    assertEquals "base config.toml not patched with user value for $label" "0" "$?"
}

function test_tomlconfig_dropin_ordering_2x() {
    run_configure_with_tomlconfig "$FIXTURE_20" $'[debug]\n  level = "info"'
    # 99-user.toml must sort after 50-replicated.toml so containerd's import merge applies it last
    assertEquals "user drop-in sorts last in conf.d" "99-user.toml" \
        "$(ls /etc/containerd/conf.d | tail -1)"
}

function test_tomlconfig_no_dropin_when_empty_2x() {
    run_configure_with_tomlconfig "$FIXTURE_20" ""
    assertEquals "no 99-user.toml when CONTAINERD_TOML_CONFIG empty (2.x)" "" \
        "$(ls "$USER_DROPIN" 2>/dev/null || true)"
}

# Reconfigure path: a prior run wrote 99-user.toml; the user then clears CONTAINERD_TOML_CONFIG
# and re-runs. Unlike config.toml/50-replicated.toml (regenerated each run), the user drop-in is
# only written, so it must be explicitly removed or its stale overrides keep applying. No rm -rf
# between the two runs here — that is the whole point.
function test_tomlconfig_stale_dropin_removed_when_emptied_2x() {
    run_configure_with_tomlconfig "$FIXTURE_20" $'[debug]\n  level = "info"'
    [ -f "$USER_DROPIN" ]
    assertEquals "precondition: 99-user.toml exists after first run (2.x)" "0" "$?"
    CONTAINERD_PRESERVE_CONFIG="" CONTAINERD_TOML_CONFIG="" containerd_configure >/dev/null
    assertEquals "stale 99-user.toml removed after emptying CONTAINERD_TOML_CONFIG (2.x)" "" \
        "$(ls "$USER_DROPIN" 2>/dev/null || true)"
}

function test_tomlconfig_leafmerge_1x() {
    run_configure_with_tomlconfig "$FIXTURE_17" $'[debug]\n  level = "info"'
    # 1.x: user value is leaf-merged into config.toml via bin/toml (stubbed as append here)
    grep -q 'level = "info"' /etc/containerd/config.toml
    assertEquals "user value leaf-merged into config.toml for 1.x" "0" "$?"
    assertEquals "no conf.d/99-user.toml on 1.x" "" \
        "$(ls "$USER_DROPIN" 2>/dev/null || true)"
}

# Bail tests: `bail` calls exit, so run containerd_configure in a subshell and assert its exit
# status. Each overrides the `containerd` stub locally to drive the rc-based validation gate
# without a real TOML parser.

function test_config_validation_bail_malformed_2x() {
    FIXTURE="$FIXTURE_20"
    rm -rf /etc/containerd
    (
        # simulate containerd rejecting a malformed merged config: `config dump` exits non-zero
        function containerd() {
            case "$*" in
                "config default") cat "$FIXTURE" ;;
                *"config dump"*) echo "toml: parse error" >&2; return 1 ;;
                *) return 0 ;;
            esac
        }
        CONTAINERD_PRESERVE_CONFIG="" CONTAINERD_TOML_CONFIG=$'[debug]\n  level = "info"' \
            containerd_configure >/dev/null 2>&1
    )
    assertEquals "bail when config dump exits non-zero (2.x malformed)" "1" "$?"
}

function test_config_validation_bail_missing_systemdcgroup_2x() {
    FIXTURE="$FIXTURE_20"
    rm -rf /etc/containerd
    (
        # config dump succeeds (rc 0) but the drop-in's SystemdCgroup is absent from the merge
        function containerd() {
            case "$*" in
                "config default") cat "$FIXTURE" ;;
                *"config dump"*) echo "version = 3" ;;
                *) return 0 ;;
            esac
        }
        CONTAINERD_PRESERVE_CONFIG="" CONTAINERD_TOML_CONFIG="" \
            containerd_configure >/dev/null 2>&1
    )
    assertEquals "bail when merged config lacks SystemdCgroup (2.x)" "1" "$?"
}

# --- upgrade logic tests (bail calls exit → wrap in subshells) ---

function test_upgrade_1_7_to_2x_allowed() {
    CONTAINERD_STEP_VERSIONS=(1.2.13 1.3.9 1.4.13 1.5.11 1.6.33 1.7.29 2.0.5)
    (CURRENT_KUBERNETES_VERSION=1.29.0 containerd_upgrade_is_possible "1.7.29" "2.0.5")
    assertEquals "1.7->2.x upgrade allowed" "0" "$?"
}

function test_upgrade_1_6_to_2x_blocked() {
    CONTAINERD_STEP_VERSIONS=(1.2.13 1.3.9 1.4.13 1.5.11 1.6.33 1.7.29 2.0.5)
    local result
    result="$( (containerd_upgrade_is_possible "1.6.33" "2.0.5") 2>&1 || true)"
    echo "$result" | grep -q "1.7"
    assertEquals "1.6->2.x blocked with 1.7 message" "0" "$?"
}

function test_upgrade_k8s_too_old_blocked() {
    CONTAINERD_STEP_VERSIONS=(1.2.13 1.3.9 1.4.13 1.5.11 1.6.33 1.7.29 2.0.5)
    local result
    result="$( (CURRENT_KUBERNETES_VERSION=1.25.0 containerd_upgrade_is_possible "1.7.29" "2.0.5") 2>&1 || true)"
    echo "$result" | grep -q "CRI v1"
    assertEquals "1.7->2.x blocked on Kubernetes < 1.26" "0" "$?"
}

function test_downgrade_2x_to_1x_blocked() {
    CONTAINERD_STEP_VERSIONS=(1.2.13 1.3.9 1.4.13 1.5.11 1.6.33 1.7.29 2.0.5)
    local result
    result="$( (containerd_upgrade_is_possible "2.0.5" "1.7.29") 2>&1 || true)"
    echo "$result" | grep -qi "not supported"
    assertEquals "2.x->1.x downgrade blocked" "0" "$?"
}

function test_same_major_minor_span_blocked() {
    CONTAINERD_STEP_VERSIONS=(1.2.13 1.3.9 1.4.13 1.5.11 1.6.33 1.7.29 2.0.5)
    local result
    result="$( (containerd_upgrade_is_possible "1.6.33" "1.9.0") 2>&1 || true)"
    echo "$result" | grep -qi "older containerd version first"
    assertEquals "same-major span > 2 minors still blocked" "0" "$?"
}

function test_migration_steps_1_7_to_2x() {
    CONTAINERD_STEP_VERSIONS=(1.2.13 1.3.9 1.4.13 1.5.11 1.6.33 1.7.29 2.0.5)
    local steps
    steps="$(containerd_migration_steps "1.7.29" "2.0.5")"
    assertEquals "migration steps 1.7->2.0" "2.0.5" "$steps"
}

# Run all tests
test_systemd_cgroup_1x
test_pause_image_1x
test_config_path_1x
test_log_level_1x
test_apparmor_ubuntu2404_1x
test_systemd_cgroup_2x
test_imports_2x
test_config_path_2x
test_log_level_2x
test_apparmor_ubuntu2404_2x
test_pause_image_2x
test_idempotent_2x
test_systemd_cgroup_2_1x
test_tomlconfig_dropin_2x "$FIXTURE_20" "containerd 2.0"
test_tomlconfig_dropin_2x "$FIXTURE_21" "containerd 2.1"
test_tomlconfig_dropin_ordering_2x
test_tomlconfig_no_dropin_when_empty_2x
test_tomlconfig_stale_dropin_removed_when_emptied_2x
test_tomlconfig_leafmerge_1x
test_config_validation_bail_malformed_2x
test_config_validation_bail_missing_systemdcgroup_2x
test_upgrade_1_7_to_2x_allowed
test_upgrade_1_6_to_2x_blocked
test_upgrade_k8s_too_old_blocked
test_downgrade_2x_to_1x_blocked
test_same_major_minor_span_blocked
test_migration_steps_1_7_to_2x

if [ "$FAILURES" -gt 0 ]; then
    echo "$FAILURES containerd test(s) failed."
    exit 1
fi
echo "All containerd tests passed."
