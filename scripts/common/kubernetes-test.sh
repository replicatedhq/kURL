#!/bin/bash

set -e

. ./scripts/common/common.sh
. ./scripts/common/kubernetes.sh
. ./scripts/distro/kubeadm/distro.sh

function test_kubernetes_node_has_image() {
    function kubernetes_node_images() {
        echo "docker.io/org/image-1:1.0
org/image-2:1.0
image-3:1.0
library/image-4:1.0
quay.io/org/image-5:1.0
quay.io/org/image-6"
    }
    export kubernetes_node_images

    assertEquals "docker.io/org/image-1:1.0 org/image-1:1.0" "0" "$(kubernetes_node_has_image "node-1" "org/image-1:1.0"; echo $?)"
    assertEquals "docker.io/org/image-1:1.0 docker.io/org/image-1:1.0" "0" "$(kubernetes_node_has_image "node-1" "docker.io/org/image-1:1.0"; echo $?)"

    assertEquals "org/image-2:1.0 org/image-2:1.0" "0" "$(kubernetes_node_has_image "node-1" "org/image-2:1.0"; echo $?)"
    assertEquals "org/image-2:1.0 docker.io/org/image-2:1.0" "0" "$(kubernetes_node_has_image "node-1" "docker.io/org/image-2:1.0"; echo $?)"

    assertEquals "image-3:1.0 image-3:1.0" "0" "$(kubernetes_node_has_image "node-1" "image-3:1.0"; echo $?)"
    assertEquals "image-3:1.0 library/image-3:1.0" "0" "$(kubernetes_node_has_image "node-1" "library/image-3:1.0"; echo $?)"
    assertEquals "image-3:1.0 docker.io/library/image-3:1.0" "0" "$(kubernetes_node_has_image "node-1" "docker.io/library/image-3:1.0"; echo $?)"

    assertEquals "library/image-4:1.0 image-4:1.0" "0" "$(kubernetes_node_has_image "node-1" "image-4:1.0"; echo $?)"
    assertEquals "library/image-4:1.0 library/image-4:1.0" "0" "$(kubernetes_node_has_image "node-1" "library/image-4:1.0"; echo $?)"
    assertEquals "library/image-4:1.0 docker.io/library/image-4:1.0" "0" "$(kubernetes_node_has_image "node-1" "docker.io/library/image-4:1.0"; echo $?)"

    assertEquals "quay.io/org/image-5:1.0 quay.io/org/image-5:1.0" "0" "$(kubernetes_node_has_image "node-1" "quay.io/org/image-5:1.0"; echo $?)"

    assertEquals "quay.io/org/image-6 quay.io/org/image-6" "0" "$(kubernetes_node_has_image "node-1" "quay.io/org/image-6"; echo $?)"
    assertEquals "quay.io/org/image-6 quay.io/org/image-6:latest" "0" "$(kubernetes_node_has_image "node-1" "quay.io/org/image-6:latest"; echo $?)"

    assertEquals "org/image-n:1.0" "1" "$(kubernetes_node_has_image "node-1" "org/image-n:1.0"; echo $?)"
    assertEquals "image-n:1.0" "1" "$(kubernetes_node_has_image "node-1" "image-n:1.0"; echo $?)"
    assertEquals "docker.io/org/image-n:1.0" "1" "$(kubernetes_node_has_image "node-1" "docker.io/org/image-n:1.0"; echo $?)"
    assertEquals "quay.io/org/image-n:1.0" "1" "$(kubernetes_node_has_image "node-1" "quay.io/org/image-n:1.0"; echo $?)"
    assertEquals "quay.io/org/image-n" "1" "$(kubernetes_node_has_image "node-1" "quay.io/org/image-n"; echo $?)"
    assertEquals "quay.io/org/image-5:2.0" "1" "$(kubernetes_node_has_image "node-1" "quay.io/org/image-5:2.0"; echo $?)"
}

# write_kubeadm_image_overrides_fixture writes a kubeadm-image-overrides file for
# $KUBERNETES_VERSION under $DIR. With no args it writes the etcd-only line used by most
# tests; "multi" writes the real four-component shape shipped in
# packages/kubernetes/1.36.5/kubeadm-image-overrides (apiserver/controller-manager/
# scheduler/etcd), so re-init gating is exercised against the actual overrides shape;
# "no-etcd" writes the same three non-etcd components with no etcd line at all, so the
# etcd re-init gate's laziness can be exercised when there is nothing for it to gate.
function write_kubeadm_image_overrides_fixture() {
    local shape="${1:-etcd-only}"
    mkdir -p "$DIR/packages/kubernetes/$KUBERNETES_VERSION"
    if [ "$shape" = "multi" ]; then
        cat > "$DIR/packages/kubernetes/$KUBERNETES_VERSION/kubeadm-image-overrides" <<EOF
kube-apiserver docker.io/kurlsh/kube-apiserver:v1.36.5 registry.k8s.io/kube-apiserver:v1.36.5
kube-controller-manager docker.io/kurlsh/kube-controller-manager:v1.36.5 registry.k8s.io/kube-controller-manager:v1.36.5
kube-scheduler docker.io/kurlsh/kube-scheduler:v1.36.5 registry.k8s.io/kube-scheduler:v1.36.5
etcd proxy.replicated.com/anonymous/registry.k8s.io/etcd:v3.6.15 registry.k8s.io/etcd:3.6.8-0
EOF
    elif [ "$shape" = "no-etcd" ]; then
        cat > "$DIR/packages/kubernetes/$KUBERNETES_VERSION/kubeadm-image-overrides" <<EOF
kube-apiserver docker.io/kurlsh/kube-apiserver:v1.36.5 registry.k8s.io/kube-apiserver:v1.36.5
kube-controller-manager docker.io/kurlsh/kube-controller-manager:v1.36.5 registry.k8s.io/kube-controller-manager:v1.36.5
kube-scheduler docker.io/kurlsh/kube-scheduler:v1.36.5 registry.k8s.io/kube-scheduler:v1.36.5
EOF
    else
        cat > "$DIR/packages/kubernetes/$KUBERNETES_VERSION/kubeadm-image-overrides" <<EOF
etcd proxy.replicated.com/anonymous/registry.k8s.io/etcd:v3.6.15 registry.k8s.io/etcd:3.6.8-0
EOF
    fi
}

function test_kubernetes_configure_kubeadm_images_etcd_override_multi_component_overrides() {
    function kubeadm_customize_config() {
        #shellcheck disable=SC2317
        true # noop
    }
    function insert_patches_strategic_merge() {
        #shellcheck disable=SC2317
        true # noop
    }
    function sleep() {
        #shellcheck disable=SC2317
        true
    }
    function kubernetes_api_is_healthy() {
        #shellcheck disable=SC2317
        true
    }

    local tmpdir=
    tmpdir=$(mktemp -d)
    DIR="$tmpdir"
    KUBERNETES_VERSION="1.36.5"
    KUBEADM_CONF_DIR="$tmpdir/kubeadm-conf"
    write_kubeadm_image_overrides_fixture multi

    local kustomize_dir="$tmpdir/kustomize"
    mkdir -p "$kustomize_dir"
    touch "$kustomize_dir/kustomization.yaml"
    local patch_dir="$KUBEADM_CONF_DIR/kurl-image-patches/$KUBERNETES_VERSION"

    # Given a fresh node (no etcd static pod manifest), a first kubeadm init against the
    # real four-component overrides file must still write a strategic patch for every
    # component, plus the etcd ClusterConfiguration override.
    local etcd_manifest="$tmpdir/manifests/etcd.yaml"
    function kubernetes_etcd_static_manifest_path() {
        #shellcheck disable=SC2317
        echo "$etcd_manifest"
    }

    kubernetes_configure_kubeadm_images "$kustomize_dir" InitConfiguration

    for component in kube-apiserver kube-controller-manager kube-scheduler etcd; do
        assertEquals "$component strategic patch should be written on first init" "0" \
            "$([ -f "$patch_dir/$component+strategic.yaml" ]; echo $?)"
    done
    assertEquals "etcd ClusterConfiguration override should be written on first init" "0" \
        "$([ -f "$kustomize_dir/kurl-etcd-image.yaml" ]; echo $?)"

    # Given a node whose control plane was already initialized, a re-run of kubeadm init
    # against the same four-component overrides file must still patch every non-etcd
    # component, and must NOT touch the running etcd.
    rm -rf "$kustomize_dir" "$patch_dir"
    mkdir -p "$kustomize_dir"
    touch "$kustomize_dir/kustomization.yaml"
    mkdir -p "$(dirname "$etcd_manifest")"
    touch "$etcd_manifest"

    kubernetes_configure_kubeadm_images "$kustomize_dir" InitConfiguration

    for component in kube-apiserver kube-controller-manager kube-scheduler; do
        assertEquals "$component strategic patch should still be written on a re-init" "0" \
            "$([ -f "$patch_dir/$component+strategic.yaml" ]; echo $?)"
    done
    assertEquals "etcd strategic patch should NOT be written on a re-init" "1" \
        "$([ -f "$patch_dir/etcd+strategic.yaml" ]; echo $?)"
    assertEquals "etcd ClusterConfiguration override should NOT be written on a re-init" "1" \
        "$([ -f "$kustomize_dir/kurl-etcd-image.yaml" ]; echo $?)"

    rm -rf "$tmpdir"
    unset -f kubeadm_customize_config insert_patches_strategic_merge kubernetes_api_is_healthy sleep kubernetes_etcd_static_manifest_path
}

function test_kubernetes_configure_kubeadm_images_etcd_override_first_init_only() {
    function kubeadm_customize_config() {
        #shellcheck disable=SC2317
        true # noop
    }
    function insert_patches_strategic_merge() {
        #shellcheck disable=SC2317
        true # noop
    }
    # kubernetes_is_first_kubeadm_init now retries the health probe via spinner_until
    # before giving up; stub sleep to a noop so a stubbed-unhealthy case below doesn't burn
    # real wall-clock time waiting out the retry budget.
    function sleep() {
        #shellcheck disable=SC2317
        true
    }
    # Default to "control plane healthy" so a plain pre-existing etcd manifest reads as a
    # genuinely completed first init, unless a case below overrides this to simulate a
    # partial/failed prior attempt.
    function kubernetes_api_is_healthy() {
        #shellcheck disable=SC2317
        true
    }

    local tmpdir=
    tmpdir=$(mktemp -d)
    DIR="$tmpdir"
    KUBERNETES_VERSION="1.36.5"
    KUBEADM_CONF_DIR="$tmpdir/kubeadm-conf"
    write_kubeadm_image_overrides_fixture

    local kustomize_dir="$tmpdir/kustomize"
    mkdir -p "$kustomize_dir"
    touch "$kustomize_dir/kustomization.yaml"

    # Given a fresh node with no existing etcd static pod manifest, the first kubeadm init
    # should still apply the securebuild etcd image/version override.
    local etcd_manifest="$tmpdir/manifests/etcd.yaml"
    function kubernetes_etcd_static_manifest_path() {
        #shellcheck disable=SC2317
        echo "$etcd_manifest"
    }

    kubernetes_configure_kubeadm_images "$kustomize_dir" InitConfiguration

    assertEquals "etcd override should be written on first init" "0" "$([ -f "$kustomize_dir/kurl-etcd-image.yaml" ]; echo $?)"
    assertEquals "etcd image should be the securebuild etcd" "0" "$(grep -q 'proxy.replicated.com/anonymous/registry.k8s.io' "$kustomize_dir/kurl-etcd-image.yaml"; echo $?)"
    assertEquals "etcd per-component strategic patch should be written on first init" "0" \
        "$([ -f "$KUBEADM_CONF_DIR/kurl-image-patches/$KUBERNETES_VERSION/etcd+strategic.yaml" ]; echo $?)"

    # Given a node whose control plane was already initialized (an etcd static pod manifest
    # already exists), a re-run of kubeadm init (e.g. a later storage-migration step) must NOT
    # write a new etcd image/version override — the running etcd must be left alone.
    rm -rf "$kustomize_dir"
    mkdir -p "$kustomize_dir"
    touch "$kustomize_dir/kustomization.yaml"
    mkdir -p "$(dirname "$etcd_manifest")"
    touch "$etcd_manifest"

    kubernetes_configure_kubeadm_images "$kustomize_dir" InitConfiguration

    assertEquals "etcd override should NOT be written on a re-init" "1" "$([ -f "$kustomize_dir/kurl-etcd-image.yaml" ]; echo $?)"
    assertEquals "etcd kubeadm patch should NOT be written on a re-init" "1" "$([ -f "$KUBEADM_CONF_DIR/kurl-image-patches/$KUBERNETES_VERSION/etcd+strategic.yaml" ]; echo $?)"

    # Given a node whose etcd static pod manifest exists but whose control plane never
    # actually became healthy (a previous kubeadm init died partway through), this must still
    # be treated as a first init: the etcd manifest alone is not proof the node has a working
    # control plane, and silently skipping the override here would fall back to an unreachable
    # upstream etcd image in an air-gapped install.
    function kubernetes_api_is_healthy() {
        #shellcheck disable=SC2317
        false
    }
    rm -rf "$kustomize_dir"
    mkdir -p "$kustomize_dir"
    touch "$kustomize_dir/kustomization.yaml"

    local output=
    output="$(kubernetes_configure_kubeadm_images "$kustomize_dir" InitConfiguration 2>&1)"

    assertEquals "etcd override should be written when a prior init never became healthy" "0" "$([ -f "$kustomize_dir/kurl-etcd-image.yaml" ]; echo $?)"
    assertEquals "etcd kubeadm patch should be written when a prior init never became healthy" "0" "$([ -f "$KUBEADM_CONF_DIR/kurl-image-patches/$KUBERNETES_VERSION/etcd+strategic.yaml" ]; echo $?)"
    assertEquals "a WARNING must be logged when falling back to first-init on an unconfirmed-healthy prior init" "0" \
        "$(echo "$output" | grep -q 'WARNING.*first init'; echo $?)"

    rm -rf "$tmpdir"
    unset -f kubeadm_customize_config insert_patches_strategic_merge kubernetes_api_is_healthy sleep kubernetes_etcd_static_manifest_path
}

function test_kubernetes_configure_kubeadm_images_no_etcd_line_skips_first_init_probe() {
    function kubeadm_customize_config() {
        #shellcheck disable=SC2317
        true # noop
    }
    function insert_patches_strategic_merge() {
        #shellcheck disable=SC2317
        true # noop
    }
    # When kubeadm-image-overrides has no "etcd" line, there is nothing for the re-init
    # gate to decide: kubernetes_is_first_kubeadm_init (and the control-plane-health probe
    # it runs) must not be called at all, even when an etcd static pod manifest already
    # exists on disk from a prior init. Stub it to fail loudly instead of silently passing
    # if it's ever invoked here.
    function kubernetes_is_first_kubeadm_init() {
        #shellcheck disable=SC2317
        fail "kubernetes_is_first_kubeadm_init must not be called when overrides has no etcd line"
    }

    local tmpdir=
    tmpdir=$(mktemp -d)
    DIR="$tmpdir"
    KUBERNETES_VERSION="1.36.5"
    KUBEADM_CONF_DIR="$tmpdir/kubeadm-conf"
    write_kubeadm_image_overrides_fixture no-etcd

    local kustomize_dir="$tmpdir/kustomize"
    mkdir -p "$kustomize_dir"
    touch "$kustomize_dir/kustomization.yaml"

    # A pre-existing etcd static pod manifest simulates a re-init against an already-live
    # control plane. With no etcd override to gate, this must have no bearing on the
    # outcome.
    local etcd_manifest="$tmpdir/manifests/etcd.yaml"
    mkdir -p "$(dirname "$etcd_manifest")"
    touch "$etcd_manifest"
    function kubernetes_etcd_static_manifest_path() {
        #shellcheck disable=SC2317
        echo "$etcd_manifest"
    }

    kubernetes_configure_kubeadm_images "$kustomize_dir" InitConfiguration

    local patch_dir="$KUBEADM_CONF_DIR/kurl-image-patches/$KUBERNETES_VERSION"
    for component in kube-apiserver kube-controller-manager kube-scheduler; do
        assertEquals "$component strategic patch should be written" "0" \
            "$([ -f "$patch_dir/$component+strategic.yaml" ]; echo $?)"
    done
    assertEquals "no etcd ClusterConfiguration override should be written" "1" \
        "$([ -f "$kustomize_dir/kurl-etcd-image.yaml" ]; echo $?)"

    rm -rf "$tmpdir"
    unset -f kubeadm_customize_config insert_patches_strategic_merge kubernetes_is_first_kubeadm_init kubernetes_etcd_static_manifest_path
}

function test_kubernetes_configure_kubeadm_images_etcd_gate_memoized() {
    function kubeadm_customize_config() {
        #shellcheck disable=SC2317
        true # noop
    }
    function insert_patches_strategic_merge() {
        #shellcheck disable=SC2317
        true # noop
    }

    # Simulate a flaky probe that disagrees with itself between calls: a plain
    # kubernetes_api_is_healthy stub that always returns the same thing can't tell a
    # memoized single evaluation apart from two independent ones. Override
    # kubernetes_is_first_kubeadm_init directly with a call-counter that flips its answer on
    # the 2nd call, so any second evaluation inside a single
    # kubernetes_configure_kubeadm_images invocation would be caught either by the call
    # count assertion below or by the strategic patch and ClusterConfiguration override
    # ending up in different states.
    KUBERNETES_IS_FIRST_KUBEADM_INIT_CALLS=0
    function kubernetes_is_first_kubeadm_init() {
        #shellcheck disable=SC2317
        KUBERNETES_IS_FIRST_KUBEADM_INIT_CALLS=$((KUBERNETES_IS_FIRST_KUBEADM_INIT_CALLS + 1))
        #shellcheck disable=SC2317
        [ "$KUBERNETES_IS_FIRST_KUBEADM_INIT_CALLS" -eq 1 ]
    }

    local tmpdir=
    tmpdir=$(mktemp -d)
    DIR="$tmpdir"
    KUBERNETES_VERSION="1.36.5"
    KUBEADM_CONF_DIR="$tmpdir/kubeadm-conf"
    write_kubeadm_image_overrides_fixture

    local kustomize_dir="$tmpdir/kustomize"
    mkdir -p "$kustomize_dir"
    touch "$kustomize_dir/kustomization.yaml"

    kubernetes_configure_kubeadm_images "$kustomize_dir" InitConfiguration

    assertEquals "kubernetes_is_first_kubeadm_init must be evaluated exactly once per invocation" \
        "1" "$KUBERNETES_IS_FIRST_KUBEADM_INIT_CALLS"
    assertEquals "etcd strategic patch and ClusterConfiguration override must move together" "0" \
        "$([ -f "$kustomize_dir/kurl-etcd-image.yaml" ] && [ -f "$KUBEADM_CONF_DIR/kurl-image-patches/$KUBERNETES_VERSION/etcd+strategic.yaml" ]; echo $?)"

    rm -rf "$tmpdir"
    unset -f kubeadm_customize_config insert_patches_strategic_merge kubernetes_is_first_kubeadm_init
    unset KUBERNETES_IS_FIRST_KUBEADM_INIT_CALLS
}

function test_kubernetes_configure_kubeadm_images_join_configuration_ignores_reinit_gate() {
    function kubeadm_customize_config() {
        #shellcheck disable=SC2317
        true # noop
    }
    function insert_patches_strategic_merge() {
        #shellcheck disable=SC2317
        true # noop
    }
    # The re-init gate only applies to InitConfiguration (see scripts/join.sh:88, which only
    # calls kubernetes_configure_kubeadm_images for JoinConfiguration on an existing control
    # plane). If kubernetes_is_first_kubeadm_init were ever called for a join, this stub would
    # make the test fail loudly instead of silently passing.
    function kubernetes_is_first_kubeadm_init() {
        #shellcheck disable=SC2317
        fail "kubernetes_is_first_kubeadm_init must not be called for JoinConfiguration"
    }

    local tmpdir=
    tmpdir=$(mktemp -d)
    DIR="$tmpdir"
    KUBERNETES_VERSION="1.36.5"
    KUBEADM_CONF_DIR="$tmpdir/kubeadm-conf"
    write_kubeadm_image_overrides_fixture

    local kustomize_dir="$tmpdir/kustomize"
    mkdir -p "$kustomize_dir"
    touch "$kustomize_dir/kustomization.yaml"

    kubernetes_configure_kubeadm_images "$kustomize_dir" JoinConfiguration

    assertEquals "etcd per-component strategic patch should be written for a join" "0" \
        "$([ -f "$KUBEADM_CONF_DIR/kurl-image-patches/$KUBERNETES_VERSION/etcd+strategic.yaml" ]; echo $?)"
    assertEquals "etcd ClusterConfiguration override is InitConfiguration-only and must NOT be written for a join" "1" \
        "$([ -f "$kustomize_dir/kurl-etcd-image.yaml" ]; echo $?)"

    rm -rf "$tmpdir"
    unset -f kubeadm_customize_config insert_patches_strategic_merge kubernetes_is_first_kubeadm_init
}

function test_kubeadm_api_is_healthy_has_bounded_timeout() {
    # kubernetes_is_first_kubeadm_init() now calls kubernetes_api_is_healthy() unbounded on the
    # re-init path (a new, previously network-free call site). Guard against that curl call
    # regressing back to no timeout, which would hang install/join indefinitely on a
    # black-holed network path instead of failing fast.
    #
    # Scoped to the kubeadm_api_is_healthy function body rather than a whole-file grep so this
    # doesn't pass spuriously because some unrelated curl call elsewhere in the file happens to
    # set these flags.
    local fn_body=
    fn_body="$(sed -n '/^function kubeadm_api_is_healthy(/,/^}/p' scripts/distro/kubeadm/distro.sh)"

    assertEquals "kubeadm_api_is_healthy curl must set --connect-timeout" "0" \
        "$(echo "$fn_body" | grep -q -- '--connect-timeout'; echo $?)"
    assertEquals "kubeadm_api_is_healthy curl must set --max-time" "0" \
        "$(echo "$fn_body" | grep -q -- '--max-time'; echo $?)"
}

# _kubeadm_api_is_healthy_assert_no_fixed_tmpfile runs kubeadm_api_is_healthy with the given
# curl stub already defined, asserts its return code, and asserts no fixed-path intermediate
# file was left on disk. rm is stubbed as a noop for the call so a regression to the old
# write-then-rm approach leaves the file behind for the assertion to catch, instead of being
# silently cleaned away before the test can observe it.
function _kubeadm_api_is_healthy_assert_no_fixed_tmpfile() {
    local expected_rc="$1"
    local message="$2"

    command rm -f /tmp/k8s-healthz.out
    function rm() {
        #shellcheck disable=SC2317
        true
    }

    assertEquals "$message" "$expected_rc" "$(kubeadm_api_is_healthy; echo $?)"
    assertEquals "kubeadm_api_is_healthy must not write a fixed /tmp healthz file" "1" \
        "$([ -f /tmp/k8s-healthz.out ]; echo $?)"

    unset -f rm
    command rm -f /tmp/k8s-healthz.out
}

function test_kubeadm_api_is_healthy_ok_body() {
    function kubernetes_api_address() {
        #shellcheck disable=SC2317
        echo "127.0.0.1:6443"
    }
    function curl() {
        #shellcheck disable=SC2317
        echo "ok"
    }

    _kubeadm_api_is_healthy_assert_no_fixed_tmpfile "0" \
        "kubeadm_api_is_healthy should return 0 when the healthz body contains 'ok'"

    unset -f kubernetes_api_address curl
}

function test_kubeadm_api_is_healthy_non_ok_body() {
    function kubernetes_api_address() {
        #shellcheck disable=SC2317
        echo "127.0.0.1:6443"
    }
    function curl() {
        #shellcheck disable=SC2317
        echo "not ready"
    }

    _kubeadm_api_is_healthy_assert_no_fixed_tmpfile "1" \
        "kubeadm_api_is_healthy should return 1 when the healthz body does not contain 'ok'"

    unset -f kubernetes_api_address curl
}

function test_kubeadm_api_is_healthy_curl_failure() {
    function kubernetes_api_address() {
        #shellcheck disable=SC2317
        echo "127.0.0.1:6443"
    }
    function curl() {
        #shellcheck disable=SC2317
        return 7
    }

    _kubeadm_api_is_healthy_assert_no_fixed_tmpfile "1" \
        "kubeadm_api_is_healthy should return 1 when curl fails outright"

    unset -f kubernetes_api_address curl
}

function test_kubernetes_version_minor() {
    assertEquals "v1.20.0" "20" "$(kubernetes_version_minor "v1.20.0")"
    assertEquals "v1.20.0" "20" "$(kubernetes_version_minor "1.20.0")"
}

function test_kubernetes_configure_pause_image_upgrade() {
    systemctl() {
        #shellcheck disable=SC2317
        true # noop
    }
    kubernetes_containerd_pause_image() {
        #shellcheck disable=SC2317
        echo "registry.k8s.io/pause:3.6"
    }

    KUBELET_FLAGS_FILE=$(mktemp)
    echo 'KUBELET_KUBEADM_ARGS="--container-runtime=remote --container-runtime-endpoint=unix:///run/containerd/containerd.sock --node-ip=10.128.0.79 --node-labels=kurl.sh/cluster=true, --pod-infra-container-image=k8s.gcr.io/pause:3.5"' > "$KUBELET_FLAGS_FILE"

    kubernetes_configure_pause_image_upgrade

    local expected='KUBELET_KUBEADM_ARGS="--container-runtime=remote --container-runtime-endpoint=unix:///run/containerd/containerd.sock --node-ip=10.128.0.79 --node-labels=kurl.sh/cluster=true, --pod-infra-container-image=registry.k8s.io/pause:3.6"'
    assertEquals "should replace correctly with flag at end" "$expected" "$(cat "$KUBELET_FLAGS_FILE")"

    echo 'KUBELET_KUBEADM_ARGS="--container-runtime=remote --container-runtime-endpoint=unix:///run/containerd/containerd.sock --node-ip=10.128.0.79 --pod-infra-container-image=k8s.gcr.io/pause:3.5 --node-labels=kurl.sh/cluster=true,"' > "$KUBELET_FLAGS_FILE"

    kubernetes_configure_pause_image_upgrade

    local expected='KUBELET_KUBEADM_ARGS="--container-runtime=remote --container-runtime-endpoint=unix:///run/containerd/containerd.sock --node-ip=10.128.0.79 --pod-infra-container-image=registry.k8s.io/pause:3.6 --node-labels=kurl.sh/cluster=true,"'
    assertEquals "should replace correctly with flag in middle" "$expected" "$(cat "$KUBELET_FLAGS_FILE")"

    rm "$KUBELET_FLAGS_FILE"
}

. shunit2
