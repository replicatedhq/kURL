#!/bin/bash
# shellcheck disable=SC2034 # VERSIONS is read by the functions sourced from script.sh

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

# write_versions_js_fixture writes a trimmed-down versions.js with the same shape as the real one
function write_versions_js_fixture() {
    cat > "$1" <<EOF
// first version of each is "latest"
module.exports.InstallerVersions = {
  kubernetes: [
    "1.19.16",
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

# line_after_marker prints the line following a versions.js marker, without whitespace
function line_after_marker() {
    grep -A1 "$1" "$2" | tail -n1 | tr -d ' '
}

function test_list_supported_minors_derives_minors_from_dockerfiles() {
    touch "$TEST_DIR/template/Dockerfile.134" "$TEST_DIR/template/Dockerfile.137" \
        "$TEST_DIR/template/Dockerfile.135" "$TEST_DIR/template/Dockerfile.136" \
        "$TEST_DIR/template/Dockerfile.1xx" "$TEST_DIR/template/script.sh"
    mkdir -p "$TEST_DIR/template/securebuild-1.37.1"

    assertEquals "37 36 35 34" "$(list_supported_minors "$TEST_DIR/template" | xargs)"
}

function test_list_supported_minors_sorts_numerically() {
    touch "$TEST_DIR/template/Dockerfile.19" "$TEST_DIR/template/Dockerfile.110" "$TEST_DIR/template/Dockerfile.199"

    assertEquals "99 10 9" "$(list_supported_minors "$TEST_DIR/template" | xargs)"
}

function test_list_supported_minors_defaults_to_cwd_and_handles_empty_dir() {
    cd "$TEST_DIR/template"
    local result=
    result="$(list_supported_minors)"
    cd "$ORIG_DIR"

    assertEquals "" "$result"
}

function test_update_available_versions_inserts_under_matching_marker() {
    touch "$TEST_DIR/template/Dockerfile.135" "$TEST_DIR/template/Dockerfile.136" "$TEST_DIR/template/Dockerfile.137"
    write_versions_js_fixture "$TEST_DIR/versions.js"

    cd "$TEST_DIR/template"
    VERSIONS=("1.37.2" "1.36.6" "1.35.9")
    KURL_VERSIONS_JS="$TEST_DIR/versions.js" update_available_versions
    cd "$ORIG_DIR"

    assertEquals '"1.37.2",' "$(line_after_marker 'cron-kubernetes-update-137' "$TEST_DIR/versions.js")"
    assertEquals '"1.36.6",' "$(line_after_marker 'cron-kubernetes-update-136' "$TEST_DIR/versions.js")"
    # 1.35.9 is already listed: nothing is added
    assertEquals "1" "$(grep -c '"1.35.9"' "$TEST_DIR/versions.js")"
    assertEquals '"1.35.9",' "$(line_after_marker 'cron-kubernetes-update-135' "$TEST_DIR/versions.js")"
    # entries keep the 4-space indentation of the array
    assertEquals "1" "$(grep -c '^    "1.37.2",$' "$TEST_DIR/versions.js")"
}

function test_update_available_versions_is_idempotent() {
    touch "$TEST_DIR/template/Dockerfile.136" "$TEST_DIR/template/Dockerfile.137"
    write_versions_js_fixture "$TEST_DIR/versions.js"

    cd "$TEST_DIR/template"
    VERSIONS=("1.37.2" "1.36.6")
    KURL_VERSIONS_JS="$TEST_DIR/versions.js" update_available_versions
    cp "$TEST_DIR/versions.js" "$TEST_DIR/versions.js.first"
    KURL_VERSIONS_JS="$TEST_DIR/versions.js" update_available_versions
    cd "$ORIG_DIR"

    assertEquals "1" "$(grep -c '"1.37.2"' "$TEST_DIR/versions.js")"
    assertEquals "1" "$(grep -c '"1.36.6"' "$TEST_DIR/versions.js")"
    local result=
    cmp -s "$TEST_DIR/versions.js.first" "$TEST_DIR/versions.js" && result=0 || result=1
    assertEquals "second run should not change versions.js" "0" "$result"
}

function test_update_available_versions_ignores_minors_without_dockerfile() {
    touch "$TEST_DIR/template/Dockerfile.137"
    write_versions_js_fixture "$TEST_DIR/versions.js"
    cp "$TEST_DIR/versions.js" "$TEST_DIR/versions.js.orig"

    cd "$TEST_DIR/template"
    VERSIONS=("1.36.6" "1.35.10")
    KURL_VERSIONS_JS="$TEST_DIR/versions.js" update_available_versions
    cd "$ORIG_DIR"

    local result=
    cmp -s "$TEST_DIR/versions.js.orig" "$TEST_DIR/versions.js" && result=0 || result=1
    assertEquals "versions.js should be unchanged" "0" "$result"
}

function test_update_available_versions_does_not_confuse_patch_prefixes() {
    touch "$TEST_DIR/template/Dockerfile.137"
    write_versions_js_fixture "$TEST_DIR/versions.js"
    sed -i 's/"1.37.1",/"1.37.10",/' "$TEST_DIR/versions.js"

    cd "$TEST_DIR/template"
    VERSIONS=("1.37.1")
    KURL_VERSIONS_JS="$TEST_DIR/versions.js" update_available_versions
    cd "$ORIG_DIR"

    assertEquals "1" "$(grep -c '"1.37.1",' "$TEST_DIR/versions.js")"
    assertEquals "1" "$(grep -c '"1.37.10",' "$TEST_DIR/versions.js")"
}

function test_update_available_versions_supports_a_new_minor_marker() {
    touch "$TEST_DIR/template/Dockerfile.137" "$TEST_DIR/template/Dockerfile.138"
    write_versions_js_fixture "$TEST_DIR/versions.js"
    sed -i '/"1.36.4",/a\    // cron-kubernetes-update-138' "$TEST_DIR/versions.js"

    cd "$TEST_DIR/template"
    VERSIONS=("1.38.0")
    KURL_VERSIONS_JS="$TEST_DIR/versions.js" update_available_versions
    cd "$ORIG_DIR"

    assertEquals '"1.38.0",' "$(line_after_marker 'cron-kubernetes-update-138' "$TEST_DIR/versions.js")"
}

# stub_curl_for_download stands in for curl in download_kubeadm: -o writes a fake binary,
# otherwise it prints "$FAKE_SHA  kubeadm" like the published .sha256 file
function stub_curl_for_download() {
    function curl() {
        local out=
        while [ $# -gt 0 ]; do
            case "$1" in
                -o) out="$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        if [ -n "$out" ]; then
            printf 'fake-kubeadm' > "$out"
        else
            echo "$FAKE_SHA  kubeadm"
        fi
    }
}

function test_github_curl_omits_authorization_header_without_token() {
    local out=
    out="$(
        unset GITHUB_TOKEN
        function curl() { echo "ARGV: $*"; echo "STDIN: $(cat)"; }
        github_curl https://api.github.com/repos/kubernetes-sigs/cri-tools/releases
    )"
    assertNotContains "$out" "Authorization"
    assertContains "$out" "https://api.github.com/repos/kubernetes-sigs/cri-tools/releases"
    assertContains "$out" "-fsS"
    assertNotContains "$out" "-L"

    out="$(
        export GITHUB_TOKEN=""
        function curl() { echo "ARGV: $*"; echo "STDIN: $(cat)"; }
        github_curl https://api.github.com/x
    )"
    assertNotContains "$out" "Authorization"
}

function test_github_curl_sends_authorization_header_on_stdin_with_token() {
    local out=
    out="$(
        export GITHUB_TOKEN="abc123"
        function curl() { echo "ARGV: $*"; echo "STDIN: $(cat)"; }
        github_curl https://api.github.com/x
    )"
    assertContains "$out" "STDIN: Authorization: token abc123"
    assertNotContains "token must not be in argv" "$(echo "$out" | grep '^ARGV:')" "abc123"
    assertContains "$out" "-H @-"
    assertNotContains "$out" "-L"
}

function test_github_curl_fails_with_clear_error_after_one_retry() {
    local result=
    result="$(
        unset GITHUB_TOKEN
        export KURL_GITHUB_RETRY_DELAY=0
        function curl() { echo "attempt" >> "$TEST_DIR/attempts"; echo "partial-body"; return 22; }
        github_curl https://api.github.com/x 2>&1 && echo "rc=0" || echo "rc=$?"
    )"
    assertContains "$result" "rc=22"
    assertNotContains "failed attempts must not print their body" "$result" "partial-body"
    assertContains "$result" "retrying"
    assertContains "$result" "rate limiting"
    assertEquals "2" "$(grep -c attempt "$TEST_DIR/attempts")"
}

# the failed first attempt prints "partial"; only the second attempt's body may come out
function test_github_curl_retry_resends_header_and_succeeds() {
    local result=
    result="$(
        export GITHUB_TOKEN="abc123"
        export KURL_GITHUB_RETRY_DELAY=0
        function curl() {
            echo "STDIN: $(cat)" >> "$TEST_DIR/attempts"
            if [ "$(grep -c STDIN "$TEST_DIR/attempts")" -lt 2 ]; then echo "partial"; return 22; fi
            echo "body"
        }
        github_curl https://api.github.com/x 2>/dev/null && echo "rc=0" || echo "rc=$?"
    )"
    assertEquals "body
rc=0" "$result"
    assertEquals "2" "$(grep -c 'STDIN: Authorization: token abc123' "$TEST_DIR/attempts")"
}

function test_download_kubeadm_accepts_matching_checksum() {
    printf 'fake-kubeadm' > "$TEST_DIR/expected"
    local result=
    result="$(
        FAKE_SHA="$(sha256_of "$TEST_DIR/expected")"
        stub_curl_for_download
        download_kubeadm 1.38.0 "$TEST_DIR" && echo ok
    )"
    assertEquals "ok" "$result"
    local executable=
    [ -x "$TEST_DIR/kubeadm" ] && executable=0 || executable=1
    assertEquals "kubeadm should be executable" "0" "$executable"
}

function test_download_kubeadm_rejects_checksum_mismatch() {
    local result=
    result="$(
        FAKE_SHA="0000000000000000000000000000000000000000000000000000000000000000"
        stub_curl_for_download
        download_kubeadm 1.38.0 "$TEST_DIR" 2>&1 && echo "rc=0" || echo "rc=$?"
    )"
    assertContains "$result" "sha256 mismatch"
    assertContains "$result" "rc=1"
    local exists=
    [ -e "$TEST_DIR/kubeadm" ] && exists=0 || exists=1
    assertEquals "mismatched kubeadm should be removed" "1" "$exists"
}

function test_download_kubeadm_rejects_invalid_checksum_file() {
    local result=
    result="$(
        FAKE_SHA="<html>"
        stub_curl_for_download
        download_kubeadm 1.38.0 "$TEST_DIR" 2>&1 && echo "rc=0" || echo "rc=$?"
    )"
    assertContains "$result" "invalid sha256"
    assertContains "$result" "rc=1"
}

# stub_generate_deps replaces the network calls of generate_version_directory. The fake kubeadm
# prints $FAKE_IMAGES, and fails if it can see GITHUB_TOKEN or FAKE_KUBEADM_FAIL is set.
function stub_generate_deps() {
    function download_kubeadm() {
        cat > "$2/kubeadm" <<EOF
#!/bin/bash
if [ -n "\${GITHUB_TOKEN:-}" ]; then echo "token leaked to kubeadm" >&2; exit 1; fi
if [ -n "\${FAKE_KUBEADM_FAIL:-}" ]; then exit 1; fi
printf '%b' "$FAKE_IMAGES"
EOF
        chmod +x "$2/kubeadm"
    }
    function github_curl() {
        printf '%s\n' '  "tag_name": "v1.38.1",' '  "tag_name": "v1.37.0",'
    }
}

function test_generate_version_directory_writes_manifest() {
    local result=
    result="$(
        cd "$TEST_DIR/template"
        export GITHUB_TOKEN="secret"
        FAKE_IMAGES='registry.k8s.io/kube-apiserver:v1.38.0\nregistry.k8s.io/coredns/coredns:v1.14.6\n'
        stub_generate_deps
        generate_version_directory 1.38.0 && echo ok
    )"
    assertEquals "ok" "$result"

    local manifest="$TEST_DIR/1.38.0/Manifest"
    assertEquals "1" "$(grep -c '^image kube-apiserver registry.k8s.io/kube-apiserver:v1.38.0$' "$manifest")"
    assertEquals "1" "$(grep -c '^image coredns registry.k8s.io/coredns/coredns:v1.14.6$' "$manifest")"
    assertEquals "1" "$(grep -c '^asset kubeadm https://dl.k8s.io/v1.38.0/bin/linux/amd64/kubeadm$' "$manifest")"
    assertEquals "1" "$(grep -c 'cri-tools/releases/download/v1.38.1/crictl-v1.38.1-linux-amd64.tar.gz$' "$manifest")"
    assertEquals "1" "$(grep -c '^asset kustomize-v5.4.3.tar.gz ' "$manifest")"
    assertEquals "no kubeadm left behind" "" "$(find "$TEST_DIR" -name kubeadm)"
}

function test_generate_version_directory_keeps_old_manifest_on_kubeadm_failure() {
    mkdir -p "$TEST_DIR/1.38.0"
    echo "old" > "$TEST_DIR/1.38.0/Manifest"

    local result=
    result="$(
        cd "$TEST_DIR/template"
        export FAKE_KUBEADM_FAIL=1
        FAKE_IMAGES='registry.k8s.io/kube-apiserver:v1.38.0\n'
        stub_generate_deps
        generate_version_directory 1.38.0 2>/dev/null && echo "rc=0" || echo "rc=$?"
    )"
    assertEquals "rc=1" "$result"
    assertEquals "old" "$(cat "$TEST_DIR/1.38.0/Manifest")"
}

function test_generate_version_directory_fails_without_images() {
    local result=
    result="$(
        cd "$TEST_DIR/template"
        FAKE_IMAGES=''
        stub_generate_deps
        generate_version_directory 1.38.0 2>&1 && echo "rc=0" || echo "rc=$?"
    )"
    assertContains "$result" "returned no images"
    assertContains "$result" "rc=1"
    local exists=
    [ -e "$TEST_DIR/1.38.0/Manifest" ] && exists=0 || exists=1
    assertEquals "no Manifest should be written" "1" "$exists"
}

function test_generate_conformance_package_writes_manifest() {
    local result=
    result="$(
        cd "$TEST_DIR/template"
        function docker() { printf '%s\n' registry.k8s.io/e2e-test-images/agnhost:2.53 registry.k8s.io/e2e-test-images/nginx:1.27.0-2; }
        generate_conformance_package 1.38.0 && echo ok
    )"
    assertEquals "ok" "$result"
    assertEquals "image conformance registry.k8s.io/conformance:v1.38.0
image nginx-1-27.0-2 registry.k8s.io/e2e-test-images/nginx:1.27.0-2" "$(cat "$TEST_DIR/1.38.0/conformance/Manifest")"
}

function test_generate_conformance_package_fails_without_nginx_image() {
    local result=
    result="$(
        cd "$TEST_DIR/template"
        function docker() { echo registry.k8s.io/e2e-test-images/agnhost:2.53; }
        generate_conformance_package 1.38.0 2>&1 && echo "rc=0" || echo "rc=$?"
    )"
    assertContains "$result" "no nginx image"
    assertContains "$result" "rc=1"
    local exists=
    [ -e "$TEST_DIR/1.38.0/conformance/Manifest" ] && exists=0 || exists=1
    assertEquals "no conformance Manifest should be written" "1" "$exists"
}

function test_find_available_versions_skips_minor_whose_build_fails() {
    touch "$TEST_DIR/template/Dockerfile.137" "$TEST_DIR/template/Dockerfile.138"
    local result=
    result="$(
        cd "$TEST_DIR/template"
        function docker() {
            case "$1" in
                build) cat > /dev/null; [ "$3" != "k8s138" ] ;;
                run) printf '%s\n' "kubelet/unknown 1.37.1-1.1 amd64" "kubelet/unknown 1.37.2-1.1 amd64" ;;
            esac
        }
        VERSIONS=()
        find_available_versions >/dev/null 2>"$TEST_DIR/stderr"
        echo "${VERSIONS[*]}"
    )"
    assertEquals "1.37.2" "$result"
    assertContains "$(cat "$TEST_DIR/stderr")" "skipping Kubernetes 1.38"
}

function test_main_works_without_github_output_from_any_cwd() {
    touch "$TEST_DIR/template/Dockerfile.137"
    write_versions_js_fixture "$TEST_DIR/versions.js"

    local result=
    result="$(
        cd /
        unset GITHUB_OUTPUT
        function generate_version_directory() { :; }
        function generate_conformance_package() { :; }
        function generate_step_versions() { :; }
        KURL_TEMPLATE_DIR="$TEST_DIR/template" KURL_VERSIONS_JS="$TEST_DIR/versions.js" main 1.37.2 >/dev/null && pwd
    )"
    assertEquals "$TEST_DIR/template" "$result"
    assertEquals '"1.37.2",' "$(line_after_marker 'cron-kubernetes-update-137' "$TEST_DIR/versions.js")"
}

# shellcheck disable=SC1091
. shunit2
