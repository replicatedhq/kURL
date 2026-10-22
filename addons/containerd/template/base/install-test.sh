#!/bin/bash

# shellcheck disable=SC2317,SC2329 # test_* functions and mocks are invoked dynamically by shunit2 discovery

set -e

# These tests stub system tools and write to (and tearDown removes) the real
# /etc/containerd and /etc/systemd/system/containerd.service.d paths, so they must
# only ever run in a disposable container — never on a host.
if [ ! -f /.dockerenv ]; then
    echo "install-test.sh writes to and removes /etc/containerd and /etc/systemd paths; run it in a container (make docker-test-shell)" >&2
    exit 1
fi

# shellcheck disable=SC1091
. ./scripts/common/common.sh
# shellcheck disable=SC1091
. ./scripts/common/containerd.sh
# shellcheck disable=SC1091
. ./addons/containerd/template/base/install.sh

function containerd_host_init() {
    # shellcheck disable=SC2317
    return 0
}

function setUp() {
    TEST_DIR="$(mktemp -d)"
    # shellcheck disable=SC2034
    DIR="$TEST_DIR"
    CONTAINERD_VERSION="9.9.9"
    mkdir -p "$DIR/addons/containerd/$CONTAINERD_VERSION"
    mkdir -p "$DIR/kustomize/kubeadm/init-patches"
    mkdir -p "$DIR/kustomize/kubeadm/join-patches"

    echo "kubeletExtraArgs-map-init" > "$DIR/addons/containerd/$CONTAINERD_VERSION/kubeadm-init-config-v1beta2.yaml"
    echo "kubeletExtraArgs-list-init" > "$DIR/addons/containerd/$CONTAINERD_VERSION/kubeadm-init-config-v1beta4.yaml"
    echo "kubeletExtraArgs-map-join" > "$DIR/addons/containerd/$CONTAINERD_VERSION/kubeadm-join-config-v1beta2.yaml"
    echo "kubeletExtraArgs-list-join" > "$DIR/addons/containerd/$CONTAINERD_VERSION/kubeadm-join-config-v1beta4.yaml"
}

function tearDown() {
    rm -rf "$TEST_DIR"
    rm -rf /etc/containerd /etc/systemd/system/containerd.service.d
    unset -f cat containerd
}

function test_containerd_pre_init_uses_v1beta2_patch_shape_by_default() {
    kubeadm_conf_api_version() { echo "v1beta3"; }

    containerd_pre_init

    assertEquals "kubeletExtraArgs-map-init" "$(cat "$DIR/kustomize/kubeadm/init-patches/containerd-kubeadm-init-config-v1beta2.yml")"
}

function test_containerd_pre_init_uses_v1beta4_patch_shape_for_kubernetes_137() {
    kubeadm_conf_api_version() { echo "v1beta4"; }

    containerd_pre_init

    assertEquals "kubeletExtraArgs-list-init" "$(cat "$DIR/kustomize/kubeadm/init-patches/containerd-kubeadm-init-config-v1beta2.yml")"
}

function test_containerd_join_uses_v1beta2_patch_shape_by_default() {
    kubeadm_conf_api_version() { echo "v1beta3"; }

    containerd_join

    assertEquals "kubeletExtraArgs-map-join" "$(cat "$DIR/kustomize/kubeadm/join-patches/containerd-kubeadm-join-config-v1beta2.yml")"
}

function test_containerd_join_uses_v1beta4_patch_shape_for_kubernetes_137() {
    kubeadm_conf_api_version() { echo "v1beta4"; }

    containerd_join

    assertEquals "kubeletExtraArgs-list-join" "$(cat "$DIR/kustomize/kubeadm/join-patches/containerd-kubeadm-join-config-v1beta2.yml")"
}

function test_containerd_pre_init_bails_on_sub_2x_containerd_with_kubernetes_137() {
    kubeadm_conf_api_version() { echo "v1beta4"; }
    CONTAINERD_VERSION="1.7.29"
    mkdir -p "$DIR/addons/containerd/$CONTAINERD_VERSION"

    local result exit_code=0
    result="$( (containerd_pre_init) 2>&1 || true)"
    assertContains "bails mentioning containerd 2.x requirement" "$result" "containerd 2.x"

    (containerd_pre_init) >/dev/null 2>&1 || exit_code=$?
    assertEquals "exits non-zero" "1" "$exit_code"
}

function test_containerd_join_bails_on_sub_2x_containerd_with_kubernetes_137() {
    kubeadm_conf_api_version() { echo "v1beta4"; }
    CONTAINERD_VERSION="1.7.29"
    mkdir -p "$DIR/addons/containerd/$CONTAINERD_VERSION"

    local exit_code=0
    (containerd_join) >/dev/null 2>&1 || exit_code=$?
    assertEquals "exits non-zero" "1" "$exit_code"
}

function test_containerd_pre_init_allows_2x_containerd_with_kubernetes_137() {
    kubeadm_conf_api_version() { echo "v1beta4"; }
    CONTAINERD_VERSION="2.3.6"
    mkdir -p "$DIR/addons/containerd/$CONTAINERD_VERSION"
    echo "kubeletExtraArgs-list-init" > "$DIR/addons/containerd/$CONTAINERD_VERSION/kubeadm-init-config-v1beta4.yaml"

    local exit_code=0
    (containerd_pre_init) >/dev/null 2>&1 || exit_code=$?
    assertEquals "does not bail" "0" "$exit_code"
}

function test_containerd_configure_proxy_no_change_short_circuits() {
    # stub cat for the duration of the call only: shunit2 itself uses cat
    cat() { printf '%s\n' 'Environment="HTTP_PROXY=http://proxy:8080" "HTTPS_PROXY=http://proxy:8081" "NO_PROXY=10.0.0.0/8"'; }
    PROXY_ADDRESS="http://proxy:8080"
    PROXY_HTTPS_ADDRESS="http://proxy:8081"
    NO_PROXY_ADDRESSES="10.0.0.0/8"
    CONTAINERD_NEEDS_RESTART=0

    local result=
    result="$(containerd_configure_proxy 2>&1)"
    unset -f cat

    if ! echo "$result" | grep -q "No changes were found"; then
        fail "expected the no-change short circuit, got: $result"
    fi
    assertEquals "no restart flagged" "0" "$CONTAINERD_NEEDS_RESTART"
    # note: shunit2's assertFalse with a string condition misbehaves under this
    # file's set -e, hence the if/fail form
    if [ -e /etc/systemd/system/containerd.service.d/http-proxy.conf ]; then
        fail "proxy file should not have been rewritten"
    fi
}

function test_containerd_configure_proxy_missing_previous_file_writes_config() {
    cat() { return 1; } # simulate a missing http-proxy.conf
    PROXY_ADDRESS="http://proxy:8080"
    PROXY_HTTPS_ADDRESS=""
    NO_PROXY_ADDRESSES=""
    CONTAINERD_NEEDS_RESTART=0

    # pipefail on: a failed probe pipeline must not abort the script (set -e)
    set -o pipefail
    containerd_configure_proxy
    set +o pipefail
    unset -f cat

    assertEquals "restart flagged" "1" "$CONTAINERD_NEEDS_RESTART"
    assertEquals "proxy file written" \
        '# Generated by kURL
[Service]
Environment="HTTP_PROXY=http://proxy:8080" "HTTPS_PROXY=" "NO_PROXY="' \
        "$(cat /etc/systemd/system/containerd.service.d/http-proxy.conf)"
}

function test_containerd_backup_probe_failure_writes_backup() {
    mkdir -p /etc/containerd
    printf 'version = 2\n' > /etc/containerd/config.toml
    containerd() { echo "boom: cannot read config" >&2; return 1; }

    containerd_backup_config_on_schema_migration
    unset -f containerd

    assertEquals "backup written" "version = 2" "$(cat /etc/containerd/config.toml.bak)"
}

function test_containerd_backup_probe_failure_does_not_accumulate() {
    mkdir -p /etc/containerd
    printf 'version = 2\n' > /etc/containerd/config.toml
    printf 'sentinel\n' > /etc/containerd/config.toml.bak
    containerd() { return 1; }

    containerd_backup_config_on_schema_migration
    unset -f containerd

    assertEquals "existing backup untouched" "sentinel" "$(cat /etc/containerd/config.toml.bak)"
    local stray=
    stray="$(ls /etc/containerd/config.toml.bak.* 2>/dev/null || true)"
    assertEquals "no timestamped copies" "" "$stray"
}

# shellcheck disable=SC1091
. shunit2
