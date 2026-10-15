#!/bin/bash

set -e

# shellcheck disable=SC1091
. ./packages/kubernetes/template/script.sh

function setUp() {
    TEST_DIR="$(mktemp -d)"
    mkdir -p "$TEST_DIR/template"
    ORIG_DIR="$(pwd)"
}

function tearDown() {
    cd "$ORIG_DIR"
    rm -rf "$TEST_DIR"
}

function test_use_securebuild_images_is_noop_without_a_securebuild_dir() {
    local version="1.37.1"
    mkdir -p "$TEST_DIR/$version"
    cat > "$TEST_DIR/$version/Manifest" <<EOF
image kube-apiserver registry.k8s.io/kube-apiserver:v1.37.1
EOF

    cd "$TEST_DIR/template"
    use_securebuild_images "$version"
    cd "$ORIG_DIR"

    assertEquals "1" "$(grep -c 'registry.k8s.io/kube-apiserver:v1.37.1' "$TEST_DIR/$version/Manifest")"
}

function test_use_securebuild_images_rewrites_manifest_for_1371() {
    local version="1.37.1"
    mkdir -p "$TEST_DIR/$version" "$TEST_DIR/template/securebuild-$version"
    cat > "$TEST_DIR/$version/Manifest" <<EOF
image kube-apiserver registry.k8s.io/kube-apiserver:v1.37.1
image kube-controller-manager registry.k8s.io/kube-controller-manager:v1.37.1
image kube-scheduler registry.k8s.io/kube-scheduler:v1.37.1
image kube-proxy registry.k8s.io/kube-proxy:v1.37.1
image coredns registry.k8s.io/coredns/coredns:v1.14.6
image pause registry.k8s.io/pause:3.10.2
image etcd registry.k8s.io/etcd:3.7.0-0
EOF
    cat > "$TEST_DIR/template/securebuild-$version/kubeadm-image-overrides" <<EOF
kube-apiserver docker.io/kurlsh/kube-apiserver:v1.37.1 registry.k8s.io/kube-apiserver:v1.37.1
kube-controller-manager docker.io/kurlsh/kube-controller-manager:v1.37.1 registry.k8s.io/kube-controller-manager:v1.37.1
kube-scheduler docker.io/kurlsh/kube-scheduler:v1.37.1 registry.k8s.io/kube-scheduler:v1.37.1
etcd docker.io/kurlsh/etcd:v3.7.0 registry.k8s.io/etcd:3.7.0-0
EOF
    cat > "$TEST_DIR/template/securebuild-$version/image-overrides" <<EOF
daemonset/kube-proxy kube-proxy docker.io/kurlsh/kube-proxy:v1.37.1 registry.k8s.io/kube-proxy:v1.37.1
deployment/coredns coredns docker.io/kurlsh/coredns:1.14.6 registry.k8s.io/coredns/coredns:v1.14.6
EOF

    cd "$TEST_DIR/template"
    use_securebuild_images "$version"
    cd "$ORIG_DIR"

    assertEquals "1" "$(grep -c 'docker.io/kurlsh/kube-apiserver:v1.37.1' "$TEST_DIR/$version/Manifest")"
    assertEquals "1" "$(grep -c 'docker.io/kurlsh/kube-controller-manager:v1.37.1' "$TEST_DIR/$version/Manifest")"
    assertEquals "1" "$(grep -c 'docker.io/kurlsh/kube-scheduler:v1.37.1' "$TEST_DIR/$version/Manifest")"
    assertEquals "1" "$(grep -c 'docker.io/kurlsh/kube-proxy:v1.37.1' "$TEST_DIR/$version/Manifest")"
    assertEquals "1" "$(grep -c 'docker.io/kurlsh/coredns:1.14.6' "$TEST_DIR/$version/Manifest")"
    assertEquals "1" "$(grep -c 'docker.io/kurlsh/etcd:v3.7.0' "$TEST_DIR/$version/Manifest")"
    # pause stays on the upstream image
    assertEquals "1" "$(grep -c 'registry.k8s.io/pause:3.10.2' "$TEST_DIR/$version/Manifest")"
    assertEquals "0" "$(grep -c 'registry.k8s.io/kube-apiserver' "$TEST_DIR/$version/Manifest" || true)"

    local result=
    [ -f "$TEST_DIR/$version/image-overrides" ] && result=0 || result=1
    assertEquals "image-overrides should be copied into the version dir" "0" "$result"
    [ -f "$TEST_DIR/$version/kubeadm-image-overrides" ] && result=0 || result=1
    assertEquals "kubeadm-image-overrides should be copied into the version dir" "0" "$result"
}

# shellcheck disable=SC1091
. shunit2
