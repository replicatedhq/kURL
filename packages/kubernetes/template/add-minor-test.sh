#!/bin/bash

# Tests for add-minor.sh. Run from the repo root (make test-shell) or any directory; requires shunit2.

ADD_MINOR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/add-minor.sh"

function setUp() {
    TEST_DIR="$(mktemp -d)"
    mkdir -p "$TEST_DIR/template"
    local minor=
    for minor in 34 35 36 37; do
        write_dockerfile "$TEST_DIR/template/Dockerfile.1${minor}" "$minor"
    done
    write_versions_js_fixture "$TEST_DIR/versions.js"
    export KURL_TEMPLATE_DIR="$TEST_DIR/template"
    export KURL_VERSIONS_JS="$TEST_DIR/versions.js"
}

function tearDown() {
    unset KURL_TEMPLATE_DIR KURL_VERSIONS_JS
    rm -rf "$TEST_DIR"
}

function write_dockerfile() {
    cat > "$1" <<EOF
FROM ubuntu:22.04
RUN apt-get update
RUN apt-get -y install curl apt-transport-https gnupg ca-certificates
RUN curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.$2/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
RUN echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.$2/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
RUN apt-get update
EOF
}

function write_versions_js_fixture() {
    cat > "$1" <<EOF
// first version of each is "latest"
module.exports.InstallerVersions = {
  kubernetes: [
    "1.19.16",
    "1.16.4",
    // cron-kubernetes-update-136
    "1.36.5",
    "1.36.4",
    // cron-kubernetes-update-137
    "1.37.1",
    // cron-kubernetes-update-135
    "1.35.9",
  ],
  flannel: [
    "0.27.4",
  ],
};
EOF
}

function run_add_minor() {
    "$ADD_MINOR" "$@" > "$TEST_DIR/out" 2>&1
}

function list_dockerfiles() {
    (cd "$TEST_DIR/template" && echo Dockerfile.*)
}

function test_add_minor_rotates_oldest_dockerfile() {
    run_add_minor 38
    assertEquals "exit code" "0" "$?"

    assertEquals "Dockerfile.135 Dockerfile.136 Dockerfile.137 Dockerfile.138" "$(list_dockerfiles)"
    assertEquals "2" "$(grep -c 'pkgs.k8s.io/core:/stable:/v1.38/deb/' "$TEST_DIR/template/Dockerfile.138")"
    assertEquals "0" "$(grep -c 'v1.34' "$TEST_DIR/template/Dockerfile.138")"
}

function test_add_minor_inserts_marker_after_first_marker_block() {
    run_add_minor 38
    assertEquals "exit code" "0" "$?"

    # the new marker goes right after the last entry of the first (latest) marker's block
    assertEquals "1" "$(grep -c '^    // cron-kubernetes-update-138$' "$TEST_DIR/versions.js")"
    assertEquals "    // cron-kubernetes-update-138" "$(grep -A1 '"1.36.4",' "$TEST_DIR/versions.js" | tail -n1)"
    assertEquals "    // cron-kubernetes-update-137" "$(grep -A1 'cron-kubernetes-update-138' "$TEST_DIR/versions.js" | tail -n1)"
    # the latest minor (1.36.5) stays the first kubernetes entry after the legacy ones
    assertEquals '"1.36.5",' "$(grep -A1 'cron-kubernetes-update-136' "$TEST_DIR/versions.js" | tail -n1 | tr -d ' ')"
}

function test_add_minor_is_idempotent() {
    run_add_minor 38
    assertEquals "first run" "0" "$?"
    cp "$TEST_DIR/versions.js" "$TEST_DIR/versions.js.first"
    cp "$TEST_DIR/template/Dockerfile.138" "$TEST_DIR/Dockerfile.138.first"

    run_add_minor 38
    assertEquals "second run" "0" "$?"

    assertEquals "Dockerfile.135 Dockerfile.136 Dockerfile.137 Dockerfile.138" "$(list_dockerfiles)"
    local result=
    cmp -s "$TEST_DIR/versions.js.first" "$TEST_DIR/versions.js" && result=0 || result=1
    assertEquals "versions.js unchanged on second run" "0" "$result"
    cmp -s "$TEST_DIR/Dockerfile.138.first" "$TEST_DIR/template/Dockerfile.138" && result=0 || result=1
    assertEquals "Dockerfile.138 unchanged on second run" "0" "$result"
    assertContains "$(cat "$TEST_DIR/out")" "skipping"
}

function test_add_minor_adds_missing_marker_when_dockerfile_exists() {
    write_dockerfile "$TEST_DIR/template/Dockerfile.138" 38

    run_add_minor 38
    assertEquals "exit code" "0" "$?"

    assertEquals "Dockerfile.134 Dockerfile.135 Dockerfile.136 Dockerfile.137 Dockerfile.138" "$(list_dockerfiles)"
    assertEquals "1" "$(grep -c 'cron-kubernetes-update-138' "$TEST_DIR/versions.js")"
}

function test_add_minor_rejects_existing_dockerfile_with_wrong_repo() {
    # e.g. a hand-copied Dockerfile.138 that still points at v1.34
    write_dockerfile "$TEST_DIR/template/Dockerfile.138" 34

    run_add_minor 38
    assertNotEquals "exit code" "0" "$?"
    assertContains "$(cat "$TEST_DIR/out")" "does not reference the v1.38/"
    assertEquals "0" "$(grep -c 'cron-kubernetes-update-138' "$TEST_DIR/versions.js")"
}

function test_add_minor_rejects_existing_dockerfile_with_mixed_repos() {
    write_dockerfile "$TEST_DIR/template/Dockerfile.138" 38
    echo "RUN echo https://pkgs.k8s.io/core:/stable:/v1.37/deb/" >> "$TEST_DIR/template/Dockerfile.138"

    run_add_minor 38
    assertNotEquals "exit code" "0" "$?"
    assertContains "$(cat "$TEST_DIR/out")" "also references other package repos: v1.37/"
}

function test_add_minor_rejects_invalid_input() {
    local input=
    for input in "" "0" "038" "1.38" "v38" "138" "38;rm" "3 8" "-1"; do
        run_add_minor "$input"
        assertNotEquals "input '$input' should be rejected" "0" "$?"
    done
    run_add_minor
    assertNotEquals "missing argument should be rejected" "0" "$?"
    run_add_minor 38 39
    assertNotEquals "extra arguments should be rejected" "0" "$?"

    assertEquals "Dockerfile.134 Dockerfile.135 Dockerfile.136 Dockerfile.137" "$(list_dockerfiles)"
    assertEquals "0" "$(grep -c 'cron-kubernetes-update-138' "$TEST_DIR/versions.js")"
}

function test_add_minor_rejects_non_consecutive_minor() {
    run_add_minor 39
    assertNotEquals "exit code" "0" "$?"
    assertContains "$(cat "$TEST_DIR/out")" "expected minor 38"

    run_add_minor 36
    assertNotEquals "exit code" "0" "$?"

    assertEquals "Dockerfile.134 Dockerfile.135 Dockerfile.136 Dockerfile.137" "$(list_dockerfiles)"
    assertEquals "0" "$(grep -c 'cron-kubernetes-update-139' "$TEST_DIR/versions.js")"
}

function test_add_minor_fails_without_marker_block() {
    sed '/cron-kubernetes-update/d' "$TEST_DIR/versions.js" > "$TEST_DIR/versions.js.tmp"
    mv "$TEST_DIR/versions.js.tmp" "$TEST_DIR/versions.js"

    run_add_minor 38
    assertNotEquals "exit code" "0" "$?"
    assertContains "$(cat "$TEST_DIR/out")" "marker block"
    assertEquals "0" "$(grep -c 'cron-kubernetes-update' "$TEST_DIR/versions.js")"
}

function test_add_minor_uses_git_mv_for_tracked_dockerfiles() {
    if ! command -v git >/dev/null 2>&1; then
        startSkipping
    fi
    (
        cd "$TEST_DIR/template" && git init -q . && git add . \
            && git -c user.email=t@example.com -c user.name=test commit -qm init
    ) >/dev/null 2>&1

    run_add_minor 38
    assertEquals "exit code" "0" "$?"

    local status=
    status="$(cd "$TEST_DIR/template" && git status --porcelain 2>/dev/null)"
    assertContains "$status" "Dockerfile.134 -> Dockerfile.138"
    assertEquals "R" "${status:0:1}"
}

function test_add_minor_runs_from_any_directory() {
    local out=
    out="$(cd / && "$ADD_MINOR" 38 2>&1)"
    assertEquals "exit code" "0" "$?"
    assertContains "$out" "Kubernetes 1.38 scaffolded"
}

# shellcheck disable=SC1091
. shunit2
