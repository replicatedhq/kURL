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
. ./scripts/common/upgrade.sh
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
# BEGIN GENERATED os-matrix: ubuntu-predicate-stubs — edit os-matrix.yaml, run 'make generate-os-matrix'
function is_ubuntu_2404() { return "${_IS_UBUNTU_2404:-1}"; }
function is_ubuntu_2604() { return "${_IS_UBUNTU_2604:-1}"; }
# END GENERATED os-matrix: ubuntu-predicate-stubs
function containerd_kubernetes_pause_image() { echo "${_PAUSE_IMAGE:-registry.k8s.io/pause:3.10}"; }
function kubernetes_containerd_pause_image() { echo "${_PAUSE_IMAGE:-registry.k8s.io/pause:3.10}"; }
function systemctl() { return 1; }      # "not active" → skip ctr pause-image import
K8S_DISTRO=kubeadm
function kubeadm_get_containerd_sock() { echo "/run/containerd/containerd.sock"; }
function kubernetes_version_minor() { echo "$1" | cut -d. -f2; }
function log() { echo "$*"; }
function logWarn() { echo "WARN: $*" 1>&2; } # matches common.sh: logWarn writes to stderr

# Shared stubs for the containerd_ensure_pause_image_pinned tests below.
#
# stub_ctr_pause_image "<list fixture>" [label-fail|list-fail]
#   `ctr ... images list` prints the fixture verbatim (or fails with list-fail), and
#   `ctr ... images label` prints "LABELED: $*" (or fails with label-fail).
_CTR_PAUSE_LIST=
_CTR_PAUSE_LIST_FAIL=0
_CTR_PAUSE_LABEL_FAIL=0
function stub_ctr_pause_image() {
    _CTR_PAUSE_LIST="$1"
    _CTR_PAUSE_LIST_FAIL=0
    _CTR_PAUSE_LABEL_FAIL=0
    case "${2:-}" in
        label-fail) _CTR_PAUSE_LABEL_FAIL=1 ;;
        list-fail) _CTR_PAUSE_LIST_FAIL=1 ;;
    esac
}
function ctr() {
    if [ "$1" = "-a" ] && [ "$2" = "/run/containerd/containerd.sock" ] && [ "$3" = "-n=k8s.io" ] && [ "$4" = "images" ] && [ "$5" = "list" ]; then
        if [ "$_CTR_PAUSE_LIST_FAIL" = "1" ]; then
            echo "ctr: failed to dial \"/run/containerd/containerd.sock\": connection refused" >&2
            return 1
        fi
        [ -n "$_CTR_PAUSE_LIST" ] && printf '%s\n' "$_CTR_PAUSE_LIST"
    elif [ "$4" = "images" ] && [ "$5" = "label" ]; then
        if [ "$_CTR_PAUSE_LABEL_FAIL" = "1" ]; then
            echo "ctr: failed to label image: permission denied" >&2
            return 1
        fi
        echo "LABELED: $*"
    fi
    return 0
}

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

function test_upgrade_1_6_to_2x_allowed() {
    CONTAINERD_STEP_VERSIONS=(1.2.13 1.3.9 1.4.13 1.5.11 1.6.33 1.7.29 2.1.5 2.2.6 2.3.6 2.4.2)
    (CURRENT_KUBERNETES_VERSION=1.29.0 containerd_upgrade_is_possible "1.6.33" "2.4.2" >/dev/null)
    assertEquals "1.6->2.x upgrade allowed (steps through 1.7)" "0" "$?"
}

function test_upgrade_1_5_to_2x_allowed() {
    CONTAINERD_STEP_VERSIONS=(1.2.13 1.3.9 1.4.13 1.5.11 1.6.33 1.7.29 2.1.5 2.2.6 2.3.6 2.4.2)
    (CURRENT_KUBERNETES_VERSION=1.29.0 containerd_upgrade_is_possible "1.5.11" "2.4.2" >/dev/null)
    assertEquals "1.5->2.x upgrade allowed (steps through 1.6 and 1.7)" "0" "$?"
}

# 1.4 -> 1.7 spans three minors, so the 1.x leg of a 1.4 -> 2.x upgrade is still blocked.
function test_upgrade_1_4_to_2x_blocked() {
    CONTAINERD_STEP_VERSIONS=(1.2.13 1.3.9 1.4.13 1.5.11 1.6.33 1.7.29 2.1.5 2.2.6 2.3.6 2.4.2)
    local result rc
    result="$( (CURRENT_KUBERNETES_VERSION=1.29.0 containerd_upgrade_is_possible "1.4.13" "2.4.2") 2>&1)"
    rc=$?
    assertEquals "1.4->2.x blocked" "1" "$rc"
    echo "$result" | grep -qi "spanning two minor versions"
    assertEquals "1.4->2.x blocked with the two-minor message" "0" "$?"
}

# containerd 2.x needs CRI v1 (Kubernetes 1.26+). The guard must fire for a 1.6 start too,
# before any 1.x step is planned.
function test_upgrade_1_6_to_2x_k8s_too_old_blocked() {
    CONTAINERD_STEP_VERSIONS=(1.2.13 1.3.9 1.4.13 1.5.11 1.6.33 1.7.29 2.1.5 2.2.6 2.3.6 2.4.2)
    local result rc
    result="$( (CURRENT_KUBERNETES_VERSION=1.25.0 containerd_upgrade_is_possible "1.6.33" "2.4.2") 2>&1)"
    rc=$?
    assertEquals "1.6->2.x blocked on Kubernetes < 1.26" "1" "$rc"
    echo "$result" | grep -q "CRI v1"
    assertEquals "1.6->2.x on Kubernetes < 1.26 prints the CRI v1 message" "0" "$?"
}

# Without a 1.7 version to step through, 1.x -> 2.x upgrades cannot be planned.
function test_upgrade_1_6_to_2x_without_1_7_step_blocked() {
    CONTAINERD_STEP_VERSIONS=(1.5.11 1.6.33 2.1.5 2.2.6)
    local result rc
    result="$( (CURRENT_KUBERNETES_VERSION=1.29.0 containerd_upgrade_is_possible "1.6.33" "2.2.6") 2>&1)"
    rc=$?
    assertEquals "1.6->2.x blocked without a 1.7 step version" "1" "$rc"
    echo "$result" | grep -q "Upgrade to containerd 1.7.x first"
    assertEquals "1.6->2.x without a 1.7 step asks for 1.7 first" "0" "$?"
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

# Usage: assert_migration_steps <description> <from> <to> <expected steps>
# Checks the steps against the in-repo step array and the array the kURL API injects, which has
# one entry per minor (latest wins across majors), 0.0.0 placeholders and is ordered by minor.
function assert_migration_steps() {
    local description="$1" from="$2" to="$3" expected="$4"
    CONTAINERD_STEP_VERSIONS=(1.2.13 1.3.9 1.4.13 1.5.11 1.6.33 1.7.29 2.1.5 2.2.6 2.3.6 2.4.2)
    assertEquals "$description" "$expected" "$(containerd_migration_steps "$from" "$to")"
    CONTAINERD_STEP_VERSIONS=(0.0.0 2.1.5 2.2.6 2.3.6 2.4.2 1.5.11 1.6.33 1.7.29)
    assertEquals "$description (server step array)" "$expected" "$(containerd_migration_steps "$from" "$to")"
}

function test_migration_steps_across_majors() {
    assert_migration_steps "migration steps 1.6->2.4" "1.6.33" "2.4.2" "1.7.29 2.4.2"
    assert_migration_steps "migration steps 1.6->2.1" "1.6.20" "2.1.5" "1.7.29 2.1.5"
    assert_migration_steps "migration steps 1.5->2.4" "1.5.11" "2.4.2" "1.6.33 1.7.29 2.4.2"
    assert_migration_steps "migration steps 1.7->2.4 unchanged" "1.7.29" "2.4.2" "2.4.2"
    assert_migration_steps "migration steps older 1.7 patch->2.4 unchanged" "1.7.25" "2.4.2" "2.4.2"
    assert_migration_steps "migration steps 1.5->1.7 unchanged" "1.5.11" "1.7.29" "1.6.33 1.7.29"
    assert_migration_steps "migration steps 2.2->2.4 unchanged" "2.2.6" "2.4.2" "2.3.6 2.4.2"
}

# containerd_evaluate_upgrade appends to a global, so run it in a subshell.
function test_evaluate_upgrade_1_6_to_2x() {
    CONTAINERD_STEP_VERSIONS=(1.2.13 1.3.9 1.4.13 1.5.11 1.6.33 1.7.29 2.1.5 2.2.6 2.3.6 2.4.2)
    local result
    result="$(
        use_os_containerd() { return 1; }
        CURRENT_KUBERNETES_VERSION=1.29.0
        CONTAINERD_INSTALL_VERSIONS=()
        containerd_evaluate_upgrade "1.6.33" "2.4.2" >/dev/null
        echo "${CONTAINERD_INSTALL_VERSIONS[*]}"
    )"
    assertEquals "evaluate upgrade 1.6->2.4 plans 1.7.29 then 2.4.2" "1.7.29 2.4.2" "$result"
}

# kURL-api keeps one step version per minor, latest wins across majors, so once containerd 2.7
# ships 1.7.29 is no longer in the array. Hosts already on 1.7 need no 1.7 step to reach 2.x.
function test_upgrade_1_7_to_2x_without_1_7_step_allowed() {
    CONTAINERD_STEP_VERSIONS=(0.0.0 2.1.5 2.2.6 2.3.6 2.4.2 2.5.0 2.6.0 2.7.0)
    (CURRENT_KUBERNETES_VERSION=1.29.0 containerd_upgrade_is_possible "1.7.29" "2.7.0" >/dev/null)
    assertEquals "1.7->2.x allowed without a 1.7 step version" "0" "$?"
    assertEquals "migration steps 1.7->2.7 without a 1.7 step version" "2.7.0" \
        "$(containerd_migration_steps "1.7.29" "2.7.0")"
}

# Once containerd 2.6 ships, 1.6.33 is no longer in the array. A 1.5 -> 2.x upgrade must bail
# with a clear message instead of skipping the 1.6 step or the whole upgrade.
function test_upgrade_1_5_to_2x_without_1_6_step_blocked() {
    CONTAINERD_STEP_VERSIONS=(0.0.0 2.1.5 2.2.6 2.3.6 2.4.2 1.5.11 2.6.0 1.7.29)
    local result rc
    result="$( (CURRENT_KUBERNETES_VERSION=1.29.0 containerd_upgrade_is_possible "1.5.11" "2.6.0") 2>&1)"
    rc=$?
    assertEquals "1.5->2.x blocked without a 1.6 step version" "1" "$rc"
    echo "$result" | grep -q "could not find a version of containerd 1.6 to step through"
    assertEquals "1.5->2.x without a 1.6 step names the missing minor" "0" "$?"
}

# If containerd_migration_steps cannot plan the steps, containerd_evaluate_upgrade must bail
# rather than leave CONTAINERD_INSTALL_VERSIONS empty and skip the upgrade.
function test_evaluate_upgrade_bails_when_steps_cannot_be_planned() {
    CONTAINERD_STEP_VERSIONS=(1.5.11 1.7.29 2.4.2)
    local result rc
    result="$( (
        use_os_containerd() { return 1; }
        containerd_upgrade_is_possible() { :; }
        CONTAINERD_INSTALL_VERSIONS=()
        containerd_evaluate_upgrade "1.5.11" "2.4.2"
        echo "INSTALL_VERSIONS=${CONTAINERD_INSTALL_VERSIONS[*]}"
    ) 2>&1)"
    rc=$?
    assertEquals "evaluate upgrade bails when the steps cannot be planned" "1" "$rc"
    echo "$result" | grep -q "Could not plan the containerd upgrade"
    assertEquals "evaluate upgrade prints the planning error" "0" "$?"
}

# Usage: run_install_upgrade_steps <airgap> <present step versions> <install versions...>
# Runs containerd_install_upgrade_steps with addon_fetch/addon_install/addon_fetch_multiple_airgap
# stubbed to print what they are called with, and the given step versions already unpacked
# under $DIR/addons/containerd.
function run_install_upgrade_steps() {
    local airgap="$1" present="$2"
    shift 2
    (
        DIR="$(mktemp -d)"
        local v
        for v in $present; do
            mkdir -p "$DIR/addons/containerd/$v"
            touch "$DIR/addons/containerd/$v/install.sh"
        done
        logStep() { :; }
        log() { :; }
        addon_fetch() { echo "fetch $2"; }
        addon_install() { echo "install $2 CONTAINERD_VERSION=$CONTAINERD_VERSION"; }
        addon_fetch_multiple_airgap() { echo "airgap-fetch $*"; }
        AIRGAP="$airgap"
        CONTAINERD_VERSION="2.4.2"
        CONTAINERD_INSTALL_VERSIONS=("$@")
        containerd_install_upgrade_steps
        echo "after CONTAINERD_VERSION=$CONTAINERD_VERSION"
        rm -rf "$DIR"
    )
}

function test_install_upgrade_steps_online() {
    local expected
    expected="$(printf '%s\n' \
        "fetch 1.7.29" \
        "install 1.7.29 CONTAINERD_VERSION=1.7.29" \
        "install 2.4.2 CONTAINERD_VERSION=2.4.2" \
        "after CONTAINERD_VERSION=2.4.2")"
    assertEquals "online 1.6->2.4 fetches and installs 1.7.29, then 2.4.2" "$expected" \
        "$(run_install_upgrade_steps "" "" 1.7.29 2.4.2)"
}

function test_install_upgrade_steps_airgap_missing_step() {
    local expected
    expected="$(printf '%s\n' \
        "airgap-fetch containerd-1.6.33 containerd-1.7.29" \
        "install 1.6.33 CONTAINERD_VERSION=1.6.33" \
        "install 1.7.29 CONTAINERD_VERSION=1.7.29" \
        "install 2.4.2 CONTAINERD_VERSION=2.4.2" \
        "after CONTAINERD_VERSION=2.4.2")"
    assertEquals "airgap 1.5->2.4 asks for the missing step packages before installing" "$expected" \
        "$(run_install_upgrade_steps "1" "2.4.2" 1.6.33 1.7.29 2.4.2)"
}

function test_install_upgrade_steps_airgap_steps_present() {
    local expected
    expected="$(printf '%s\n' \
        "install 1.7.29 CONTAINERD_VERSION=1.7.29" \
        "install 2.4.2 CONTAINERD_VERSION=2.4.2" \
        "after CONTAINERD_VERSION=2.4.2")"
    assertEquals "airgap 1.6->2.4 with the step in the bundle fetches nothing" "$expected" \
        "$(run_install_upgrade_steps "1" "1.7.29 2.4.2" 1.7.29 2.4.2)"
}

function test_kubernetes_137_blocked_on_sub_2x_containerd() {
    kubeadm_conf_api_version() { echo "v1beta4"; }
    local result
    result="$( (containerd_verify_kubernetes_1_37_compatibility "1.7.29") 2>&1 || true)"
    echo "$result" | grep -q "containerd 2.x"
    assertEquals "Kubernetes 1.37+ blocked on containerd 1.7.29" "0" "$?"
}

function test_kubernetes_137_allowed_on_2x_containerd() {
    kubeadm_conf_api_version() { echo "v1beta4"; }
    (containerd_verify_kubernetes_1_37_compatibility "2.0.5")
    assertEquals "Kubernetes 1.37+ allowed on containerd 2.0.5" "0" "$?"
}

function test_pre_137_kubernetes_allowed_on_sub_2x_containerd() {
    kubeadm_conf_api_version() { echo "v1beta3"; }
    (containerd_verify_kubernetes_1_37_compatibility "1.7.29")
    assertEquals "Kubernetes <1.37 allowed on containerd 1.7.29" "0" "$?"
}

# Usage: run_136_guard <k8s target> <local k8s> <remote node k8s> <containerd> [os containerd]
# The optional fifth argument makes the node use the OS containerd at that version, or
# "none" when it is not installed yet. A remote node version prefixed with "primary:" is
# a remote primary, otherwise a secondary.
# Runs the guard in a subshell so the globals it sets do not leak into later tests, and
# prints its output.
function run_136_guard() {
    (
        use_os_containerd() { [ -n "$OS_CONTAINERD" ]; }
        containerd_installed_version() { [ "$OS_CONTAINERD" = "none" ] || echo "$OS_CONTAINERD"; }
        OS_CONTAINERD="$5"
        KUBERNETES_VERSION="$1"
        CURRENT_KUBERNETES_VERSION="$2"
        KUBERNETES_REMOTE_PRIMARIES=() KUBERNETES_SECONDARIES=()
        case "$3" in
            "") ;;
            primary:*) KUBERNETES_REMOTE_PRIMARIES=(node2) KUBERNETES_REMOTE_PRIMARY_VERSIONS=("${3#primary:}") ;;
            *) KUBERNETES_SECONDARIES=(node2) KUBERNETES_SECONDARY_VERSIONS=("$3") ;;
        esac
        containerd_bail_if_kubernetes_1_36_unsupported "$4"
    ) 2>&1
}

# Rows that bail must print the given message; rows that pass must not mention containerd 2.x.
function test_kubernetes_136_guard() {
    local expected target local_version remote_version containerd os_containerd message description output rc
    while IFS='|' read -r expected target local_version remote_version containerd os_containerd message description; do
        output="$(run_136_guard "$target" "$local_version" "$remote_version" "$containerd" "$os_containerd")"
        rc=$?
        assertEquals "$description" "$expected" "$rc"
        if [ -n "$message" ]; then
            echo "$output" | grep -qF "$message"
            assertEquals "$description: prints \"$message\"" "0" "$?"
        else
            echo "$output" | grep -qF "containerd 2.x"
            assertEquals "$description: prints no containerd 2.x error" "1" "$?"
        fi
    done <<'EOF'
1|1.36.1|||1.7.29||Select containerd 2.x to install or upgrade|new 1.36 cluster on containerd 1.7.29 bails
1|1.36.1|1.35.4||1.7.29||Select containerd 2.x to install or upgrade|upgrade 1.35 -> 1.36 on containerd 1.7.29 bails
1|1.36.1|1.25.16||1.7.29||Upgrade to containerd 1.7.x and Kubernetes 1.26 or later first|upgrade 1.25 -> 1.36 on containerd 1.7.29 asks for 1.26 first
1|1.36.2|1.36.1|1.35.4|1.7.29||Select containerd 2.x to install or upgrade|re-run on a 1.36 primary with a 1.35 secondary on containerd 1.7.29 bails
1|1.36.2|1.36.1|primary:1.35.4|1.7.29||Select containerd 2.x to install or upgrade|re-run on a 1.36 primary with a 1.35 remote primary on containerd 1.7.29 bails
0|1.36.2|1.36.1|1.36.1|1.7.29|||re-run on a 1.36 cluster on containerd 1.7.29 passes
0|1.36.2|1.36.1|primary:1.36.1|1.7.29|||re-run on a 1.36 HA cluster on containerd 1.7.29 passes
0|1.36.1|||2.3.6|||new 1.36 cluster on containerd 2.3.6 passes
0|1.35.4|||1.7.29|||new 1.35 cluster on containerd 1.7.29 passes
1|1.36.1|||2.4.2|1.7.28|provided by the Operating System|new 1.36 cluster on OS containerd 1.7.28 bails even with 2.4.2 selected
1|1.36.1|1.35.4||2.4.2|1.7.28|provided by the Operating System|upgrade 1.35 -> 1.36 on OS containerd 1.7.28 bails
0|1.36.1|||1.7.29|2.2.1||new 1.36 cluster on OS containerd 2.2.1 passes with 1.7.29 selected
0|1.36.1|||1.7.29|none||new 1.36 cluster before the OS containerd is installed passes
0|1.36.2|1.36.1||2.4.2|1.7.28||re-run on a 1.36 cluster on OS containerd 1.7.28 passes
EOF
}

# test-addon CI resolves the installer base (scripts/common/containerd.sh, which defines
# containerd_verify_kubernetes_1_37_compatibility) from staging, built from main — while the
# add-on package under test (containerd_pre_init/containerd_join below) is built from this
# branch. Until this PR merges, main's base does not define the guard function, so it must not
# be a hard dependency of pre_init/join.
function test_pre_init_tolerates_missing_137_guard() {
    kubeadm_conf_api_version() { echo "v1beta4"; }
    CONTAINERD_VERSION="1.7.29"
    local result rc
    result="$( (
        containerd_host_init() { :; }
        unset -f containerd_verify_kubernetes_1_37_compatibility
        containerd_pre_init
    ) 2>&1 )"
    rc=$?
    assertEquals "containerd_pre_init exits 0 when the 1.37 guard is undefined" "0" "$rc"
    echo "$result" | grep -qi "command not found"
    assertEquals "containerd_pre_init does not error with 'command not found'" "1" "$?"
}

function test_join_tolerates_missing_137_guard() {
    kubeadm_conf_api_version() { echo "v1beta4"; }
    CONTAINERD_VERSION="1.7.29"
    local result rc
    result="$( (
        containerd_host_init() { :; }
        unset -f containerd_verify_kubernetes_1_37_compatibility
        containerd_join
    ) 2>&1 )"
    rc=$?
    assertEquals "containerd_join exits 0 when the 1.37 guard is undefined" "0" "$rc"
    echo "$result" | grep -qi "command not found"
    assertEquals "containerd_join does not error with 'command not found'" "1" "$?"
}

# --- runc selection tests ---

# Runs containerd_install_runc against a fake /usr/bin/containerd printing $1 (no binary when
# empty) and an add-on src dir holding runc and, unless $2 is "no-asset", runc-1.3.6. Prints the
# installed runc content, stores the exit code in RUNC_RC and the function's output in RUNC_LOG.
RUNC_LOG="$(mktemp)"
function run_install_runc() {
    local version_output="$1" asset="$2"
    local src dest
    src="$(mktemp -d)"
    dest="$(mktemp -d)/runc"
    mkdir -p "$src/assets"
    echo "runc-1.5.1" > "$src/assets/runc"
    if [ "$asset" != "no-asset" ]; then
        echo "runc-1.3.6" > "$src/assets/runc-1.3.6"
    fi
    rm -f /usr/bin/containerd
    if [ -n "$version_output" ]; then
        printf '#!/bin/sh\necho "%s"\n' "$version_output" > /usr/bin/containerd
        chmod +x /usr/bin/containerd
    fi
    (
        which() { echo "$dest"; }
        try_1m_stderr() { "$@"; }
        containerd_install_runc "$src"
    ) >"$RUNC_LOG" 2>&1
    RUNC_RC=$?
    rm -f /usr/bin/containerd
    cat "$dest" 2>/dev/null || true
}

function test_install_runc_containerd_1x() {
    CONTAINERD_VERSION="2.3.6"
    local installed
    installed="$(run_install_runc "containerd containerd.io 1.6.33 d2d58213f83a351ca8f528a95fbd145f5654e957")"
    assertEquals "2.x add-on on containerd 1.x installs runc 1.3.6" "runc-1.3.6" "$installed"
}

function test_install_runc_containerd_2x() {
    CONTAINERD_VERSION="2.3.6"
    local installed
    installed="$(run_install_runc "containerd github.com/containerd/containerd/v2 v2.3.6 fcd43222d6b07379a4be9786bda52438f0dd16a1")"
    assertEquals "2.x add-on on containerd 2.x installs the add-on runc" "runc-1.5.1" "$installed"
}

function test_install_runc_missing_asset_bails() {
    CONTAINERD_VERSION="2.3.6"
    run_install_runc "containerd containerd.io 1.6.33 d2d58213f83a351ca8f528a95fbd145f5654e957" "no-asset" >/dev/null
    assertEquals "2.x add-on on containerd 1.x bails without runc-1.3.6" "1" "$RUNC_RC"
}

function test_install_runc_unknown_version() {
    CONTAINERD_VERSION="2.3.6"
    local installed
    installed="$(run_install_runc "")"
    assertEquals "unknown containerd version installs the add-on runc" "runc-1.5.1" "$installed"
    run_install_runc "" >/dev/null
    grep -q "/usr/bin/containerd --version: .*No such file or directory" "$RUNC_LOG"
    assertEquals "unknown containerd version warning includes the version check error" "0" "$?"
}

function test_install_runc_1x_addon() {
    CONTAINERD_VERSION="1.7.30"
    local installed
    installed="$(run_install_runc "containerd containerd.io 1.7.30 abc" "no-asset")"
    assertEquals "1.x add-on installs the add-on runc" "runc-1.5.1" "$installed"
}

# --- add-on override version test ---
# The 2.x add-ons install 1.6.33 on rhel-7. Re-running one there must not bail.

function test_override_version_rerun() {
    local dir
    dir="$(mktemp -d)"
    mkdir -p "$dir/addons/containerd/2.4.2"
    echo "dockerout rhel-7 addons/containerd/template/Dockerfile.centos7 1.6.33" > "$dir/addons/containerd/2.4.2/Manifest"

    local result
    result="$( (
        DIR="$dir" LSB_DIST=centos DIST_VERSION_MAJOR=7
        use_os_containerd() { return 1; }
        containerd_evaluate_upgrade 1.6.33 2.4.2 >/dev/null
        echo "${CONTAINERD_INSTALL_VERSIONS[*]}"
    ) 2>&1 )"
    assertEquals "re-run of 2.4.2 add-on on centos 7 with 1.6.33 installed" "2.4.2" "$result"

    result="$( (
        DIR="$dir" LSB_DIST=rocky DIST_VERSION_MAJOR=8
        CONTAINERD_STEP_VERSIONS=(1.6.33 1.7.29 2.4.2)
        use_os_containerd() { return 1; }
        containerd_evaluate_upgrade 1.6.33 2.4.2 >/dev/null
        echo "${CONTAINERD_INSTALL_VERSIONS[*]}"
    ) 2>&1 )"
    assertEquals "1.6.33 -> 2.4.2 on rocky 8 steps through 1.7" "1.7.29 2.4.2" "$result"
    rm -rf "$dir"
}

# --- containerd_ensure_pause_image_pinned tests (sc-140018) ---

PAUSE_310_UNPINNED="registry.k8s.io/pause:3.10 application/vnd.oci.image.index.v1+json sha256:deadbeef 300.0KiB linux/amd64 -"
PAUSE_310_LABELED="LABELED: -a /run/containerd/containerd.sock -n=k8s.io images label -- registry.k8s.io/pause:3.10 io.cri-containerd.pinned=pinned"

function test_ensure_pause_image_pinned_pins_when_unpinned() {
    local result
    result="$( (
        systemctl() { [ "$1" = "is-active" ]; }
        stub_ctr_pause_image "$PAUSE_310_UNPINNED"
        CONTAINERD_VERSION="1.7.29"
        touch /etc/containerd/config.toml
        containerd_ensure_pause_image_pinned
    ) 2>&1 )"
    echo "$result" | grep -qF "$PAUSE_310_LABELED"
    assertEquals "pins an unpinned pause image already present in containerd" "0" "$?"
}

function test_ensure_pause_image_pinned_with_multiple_images_not_first_or_only() {
    local result
    result="$( (
        systemctl() { [ "$1" = "is-active" ]; }
        stub_ctr_pause_image "$(printf '%s\n%s\n%s' \
            "registry.k8s.io/kube-apiserver:v1.31.14 application/vnd.oci.image.index.v1+json sha256:aaaaaaaa 200.0KiB linux/amd64 -" \
            "$PAUSE_310_UNPINNED" \
            "registry.k8s.io/coredns/coredns:v1.11.3 application/vnd.oci.image.index.v1+json sha256:cccccccc 400.0KiB linux/amd64 -")"
        CONTAINERD_VERSION="1.7.29"
        touch /etc/containerd/config.toml
        containerd_ensure_pause_image_pinned
    ) 2>&1 )"
    echo "$result" | grep -qF "$PAUSE_310_LABELED"
    assertEquals "pins the pause image when containerd has several images imported and the pause image is neither first nor alone" "0" "$?"
    assertEquals "labels only the pause image" "1" "$(echo "$result" | grep -c "LABELED")"
}

function test_ensure_pause_image_pinned_noop_when_already_pinned() {
    local result
    result="$( (
        systemctl() { [ "$1" = "is-active" ]; }
        stub_ctr_pause_image "registry.k8s.io/pause:3.10 application/vnd.oci.image.index.v1+json sha256:deadbeef 300.0KiB linux/amd64 io.cri-containerd.pinned=pinned"
        CONTAINERD_VERSION="1.7.29"
        touch /etc/containerd/config.toml
        containerd_ensure_pause_image_pinned
    ) 2>&1 )"
    echo "$result" | grep -q "LABELED"
    assertEquals "does not re-label an already-pinned pause image" "1" "$?"
}

function test_ensure_pause_image_pinned_noop_when_not_imported() {
    # e.g. a fresh install before images are loaded; kubernetes_load_images pins once it imports.
    local result
    result="$( (
        systemctl() { [ "$1" = "is-active" ]; }
        stub_ctr_pause_image ""
        CONTAINERD_VERSION="1.7.29"
        touch /etc/containerd/config.toml
        containerd_ensure_pause_image_pinned
    ) 2>&1 )"
    echo "$result" | grep -qE "LABELED|WARN"
    assertEquals "does not pin or warn about an image containerd has not imported" "1" "$?"
}

function test_ensure_pause_image_pinned_noop_when_containerd_inactive() {
    local result
    result="$( (
        systemctl() { echo "inactive"; return 3; }
        ctr() { echo "LABELED: $*"; }
        CONTAINERD_VERSION="1.7.29"
        touch /etc/containerd/config.toml
        containerd_ensure_pause_image_pinned
    ) 2>&1 )"
    echo "$result" | grep -q "LABELED"
    assertEquals "does not call ctr when containerd is genuinely inactive" "1" "$?"
    echo "$result" | grep -qi "WARN"
    assertEquals "does not log a warning for a legitimate inactive/failed state" "1" "$?"
}

function test_ensure_pause_image_pinned_noop_on_2x_without_sandbox_image() {
    local result
    result="$( (
        systemctl() { [ "$1" = "is-active" ]; }
        kubernetes_containerd_pause_image() { echo ""; } # 2.x: not exposed in config.toml
        ctr() { echo "LABELED: $*"; }
        CONTAINERD_VERSION="2.2.6"
        touch /etc/containerd/config.toml
        containerd_ensure_pause_image_pinned
    ) 2>&1 )"
    echo "$result" | grep -q "LABELED"
    assertEquals "no-ops on containerd 2.x, which never exposes sandbox_image" "1" "$?"
}

function test_ensure_pause_image_pinned_warns_on_list_failure() {
    local result
    local exit_code
    result="$( (
        systemctl() { [ "$1" = "is-active" ]; }
        stub_ctr_pause_image "" list-fail
        CONTAINERD_VERSION="1.7.29"
        touch /etc/containerd/config.toml
        containerd_ensure_pause_image_pinned
    ) 2>&1 )"
    exit_code="$?"
    echo "$result" | grep -q "Failed to list containerd images"
    assertEquals "logs a warning when ctr images list fails" "0" "$?"
    echo "$result" | grep -q "LABELED"
    assertEquals "does not try to pin when ctr images list fails" "1" "$?"
    assertEquals "does not abort the caller when ctr images list fails" "0" "$exit_code"
}

function test_ensure_pause_image_pinned_survives_sock_resolution_failure_under_set_e() {
    local result
    local exit_code
    result="$( (
        set -e # install.sh runs with set -e; resolving the containerd socket must not be exempt from it
        systemctl() { [ "$1" = "is-active" ]; }
        kubeadm_get_containerd_sock() { return 1; } # e.g. an unimplemented distro shim
        ctr() { echo "LABELED: $*"; }
        CONTAINERD_VERSION="1.7.29"
        touch /etc/containerd/config.toml
        containerd_ensure_pause_image_pinned
    ) 2>&1 )"
    exit_code="$?"
    echo "$result" | grep -q "Failed to resolve the containerd socket"
    assertEquals "logs a warning when containerd sock resolution fails" "0" "$?"
    echo "$result" | grep -q "LABELED"
    assertEquals "does not call ctr when containerd sock resolution fails" "1" "$?"
    assertEquals "does not abort the caller when containerd sock resolution fails" "0" "$exit_code"
}

function test_ensure_pause_image_pinned_warns_on_label_failure() {
    local result
    local exit_code
    result="$( (
        systemctl() { [ "$1" = "is-active" ]; }
        stub_ctr_pause_image "$PAUSE_310_UNPINNED" label-fail
        CONTAINERD_VERSION="1.7.29"
        touch /etc/containerd/config.toml
        containerd_ensure_pause_image_pinned
    ) 2>&1 )"
    exit_code="$?"
    echo "$result" | grep -q "Failed to pin containerd pause image"
    assertEquals "logs a warning when ctr images label fails" "0" "$?"
    echo "$result" | grep "Failed to pin containerd pause image" | grep -q "permission denied"
    assertEquals "the warning itself (not just stray stderr) captures the underlying error, like the list-failure branch does" "0" "$?"
    assertEquals "does not abort the caller when ctr images label fails" "0" "$exit_code"
}

function test_ensure_pause_image_pinned_noop_when_containerd_version_unset() {
    local result
    result="$( (
        systemctl() { echo "SYSTEMCTL_CALLED"; }
        ctr() { echo "CTR_CALLED: $*"; }
        CONTAINERD_VERSION=""
        touch /etc/containerd/config.toml
        containerd_ensure_pause_image_pinned
    ) 2>&1 )"
    echo "$result" | grep -qE "SYSTEMCTL_CALLED|CTR_CALLED"
    assertEquals "no-ops when CONTAINERD_VERSION is unset (e.g. Docker-CRI host)" "1" "$?"
}

function test_ensure_pause_image_pinned_noop_when_config_toml_missing() {
    local result
    result="$( (
        systemctl() { echo "SYSTEMCTL_CALLED"; }
        ctr() { echo "CTR_CALLED: $*"; }
        CONTAINERD_VERSION="1.7.29"
        rm -f /etc/containerd/config.toml
        containerd_ensure_pause_image_pinned
    ) 2>&1 )"
    echo "$result" | grep -qE "SYSTEMCTL_CALLED|CTR_CALLED"
    assertEquals "no-ops when /etc/containerd/config.toml is missing" "1" "$?"
}

# install_cri pins right after the containerd add-on imports the new pause image and restarts
# containerd.
function test_install_cri_pins_pause_image_after_containerd_install() {
    local result
    result="$( (
        report_install_containerd() { echo "INSTALL_CONTAINERD"; }
        containerd_ensure_pause_image_pinned() { echo "PIN"; }
        DOCKER_VERSION=""
        CONTAINERD_VERSION="1.7.29"
        install_cri
    ) 2>&1 )"
    assertEquals "install_cri installs containerd, then pins the pause image" "$(printf '%s\n%s' "INSTALL_CONTAINERD" "PIN")" "$result"
}

function test_install_cri_does_not_pin_on_docker() {
    local result
    result="$( (
        report_install_docker() { echo "INSTALL_DOCKER"; }
        containerd_ensure_pause_image_pinned() { echo "PIN"; }
        DOCKER_VERSION="20.10.17"
        CONTAINERD_VERSION=""
        install_cri
    ) 2>&1 )"
    assertEquals "install_cri on docker does not call the containerd pause pin" "INSTALL_DOCKER" "$result"
}

# 2.x add-ons that install 1.6.33 on rhel-7 do not cross a major version there, so no 1.7 step.
function test_override_no_bridge_step_on_rhel7() {
    local dir
    dir="$(mktemp -d)"
    mkdir -p "$dir/addons/containerd/2.4.2"
    echo "dockerout rhel-7 addons/containerd/template/Dockerfile.centos7 1.6.33" > "$dir/addons/containerd/2.4.2/Manifest"

    local result
    result="$( (
        DIR="$dir" LSB_DIST=amzn DIST_VERSION_MAJOR=2
        CONTAINERD_STEP_VERSIONS=(1.5.11 1.6.33 1.7.29 2.4.2)
        use_os_containerd() { return 1; }
        containerd_evaluate_upgrade 1.5.11 2.4.2 >/dev/null
        echo "${CONTAINERD_INSTALL_VERSIONS[*]}"
    ) 2>&1 )"
    assertEquals "1.5 -> 2.4.2 add-on on amazon linux 2 adds no 1.7.29 step" "2.4.2" "$result"
    rm -rf "$dir"
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
test_upgrade_1_6_to_2x_allowed
test_upgrade_1_5_to_2x_allowed
test_upgrade_1_4_to_2x_blocked
test_upgrade_1_6_to_2x_k8s_too_old_blocked
test_upgrade_1_6_to_2x_without_1_7_step_blocked
test_upgrade_k8s_too_old_blocked
test_downgrade_2x_to_1x_blocked
test_same_major_minor_span_blocked
test_migration_steps_1_7_to_2x
test_migration_steps_across_majors
test_evaluate_upgrade_1_6_to_2x
test_upgrade_1_7_to_2x_without_1_7_step_allowed
test_upgrade_1_5_to_2x_without_1_6_step_blocked
test_evaluate_upgrade_bails_when_steps_cannot_be_planned
test_install_upgrade_steps_online
test_install_upgrade_steps_airgap_missing_step
test_install_upgrade_steps_airgap_steps_present
test_kubernetes_137_blocked_on_sub_2x_containerd
test_kubernetes_137_allowed_on_2x_containerd
test_pre_137_kubernetes_allowed_on_sub_2x_containerd
test_kubernetes_136_guard
test_pre_init_tolerates_missing_137_guard
test_join_tolerates_missing_137_guard
test_install_runc_containerd_1x
test_install_runc_containerd_2x
test_install_runc_missing_asset_bails
test_install_runc_unknown_version
test_install_runc_1x_addon
test_override_version_rerun
test_ensure_pause_image_pinned_pins_when_unpinned
test_ensure_pause_image_pinned_with_multiple_images_not_first_or_only
test_ensure_pause_image_pinned_noop_when_already_pinned
test_ensure_pause_image_pinned_noop_when_not_imported
test_ensure_pause_image_pinned_noop_when_containerd_inactive
test_ensure_pause_image_pinned_noop_on_2x_without_sandbox_image
test_ensure_pause_image_pinned_warns_on_list_failure
test_ensure_pause_image_pinned_survives_sock_resolution_failure_under_set_e
test_ensure_pause_image_pinned_warns_on_label_failure
test_ensure_pause_image_pinned_noop_when_containerd_version_unset
test_ensure_pause_image_pinned_noop_when_config_toml_missing
test_install_cri_pins_pause_image_after_containerd_install
test_install_cri_does_not_pin_on_docker
test_override_no_bridge_step_on_rhel7

if [ "$FAILURES" -gt 0 ]; then
    echo "$FAILURES containerd test(s) failed."
    exit 1
fi
echo "All containerd tests passed."
