#!/bin/bash
# shellcheck disable=SC2034 # VERSIONS is read by the functions sourced from script.sh

# shellcheck disable=SC1091
. ./packages/kubernetes/template/script.sh
# script.sh turns on errexit; shunit2 needs it off so a failing assertion is reported and the rest of
# the test still runs. Tests that check errexit behaviour run script.sh in a separate bash.
set +e

# must_cd changes directory or fails the test: errexit is off, so a failed cd would otherwise run the
# rest of the test (and its sed -i calls) in the wrong directory
function must_cd() {
    cd "$1" || { fail "cd $1"; return 1; }
}

function setUp() {
    TEST_DIR="$(mktemp -d)"
    mkdir -p "$TEST_DIR/template"
    ORIG_DIR="$(pwd)"
}

function tearDown() {
    must_cd "$ORIG_DIR" || return 1
    rm -rf "$TEST_DIR"
}

function test_use_securebuild_images_is_noop_without_a_securebuild_dir() {
    local version="1.37.1"
    mkdir -p "$TEST_DIR/$version"
    cat > "$TEST_DIR/$version/Manifest" <<EOF
image kube-apiserver registry.k8s.io/kube-apiserver:v1.37.1
EOF

    must_cd "$TEST_DIR/template" || return 1
    use_securebuild_images "$version"
    must_cd "$ORIG_DIR" || return 1
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

    must_cd "$TEST_DIR/template" || return 1
    use_securebuild_images "$version"
    must_cd "$ORIG_DIR" || return 1
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

# same_content succeeds when two files are byte-identical (cmp is not installed on every test image)
function same_content() {
    [ "$(cksum < "$1")" = "$(cksum < "$2")" ]
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
    must_cd "$TEST_DIR/template" || return 1
    local result=
    result="$(list_supported_minors)"
    must_cd "$ORIG_DIR" || return 1
    assertEquals "" "$result"
}

function test_update_available_versions_inserts_under_matching_marker() {
    touch "$TEST_DIR/template/Dockerfile.135" "$TEST_DIR/template/Dockerfile.136" "$TEST_DIR/template/Dockerfile.137"
    write_versions_js_fixture "$TEST_DIR/versions.js"

    must_cd "$TEST_DIR/template" || return 1
    VERSIONS=("1.37.2" "1.36.6" "1.35.9")
    KURL_VERSIONS_JS="$TEST_DIR/versions.js" update_available_versions
    must_cd "$ORIG_DIR" || return 1
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

    must_cd "$TEST_DIR/template" || return 1
    VERSIONS=("1.37.2" "1.36.6")
    KURL_VERSIONS_JS="$TEST_DIR/versions.js" update_available_versions
    cp "$TEST_DIR/versions.js" "$TEST_DIR/versions.js.first"
    KURL_VERSIONS_JS="$TEST_DIR/versions.js" update_available_versions
    must_cd "$ORIG_DIR" || return 1
    assertEquals "1" "$(grep -c '"1.37.2"' "$TEST_DIR/versions.js")"
    assertEquals "1" "$(grep -c '"1.36.6"' "$TEST_DIR/versions.js")"
    local result=
    same_content "$TEST_DIR/versions.js.first" "$TEST_DIR/versions.js" && result=0 || result=1
    assertEquals "second run should not change versions.js" "0" "$result"
}

function test_update_available_versions_lists_explicit_version_without_dockerfile() {
    # e.g. a human publishes 1.36.6 after Dockerfile.136 was rotated out; its marker is still there
    touch "$TEST_DIR/template/Dockerfile.137"
    write_versions_js_fixture "$TEST_DIR/versions.js"

    must_cd "$TEST_DIR/template" || return 1
    VERSIONS=("1.36.6")
    KURL_VERSIONS_JS="$TEST_DIR/versions.js" update_available_versions
    must_cd "$ORIG_DIR" || return 1
    assertEquals '"1.36.6",' "$(line_after_marker 'cron-kubernetes-update-136' "$TEST_DIR/versions.js")"
}

function test_update_available_versions_fails_without_marker() {
    touch "$TEST_DIR/template/Dockerfile.137" "$TEST_DIR/template/Dockerfile.138"
    write_versions_js_fixture "$TEST_DIR/versions.js"
    cp "$TEST_DIR/versions.js" "$TEST_DIR/versions.js.orig"

    local result=
    result="$(
        must_cd "$TEST_DIR/template" || return 1
        VERSIONS=("1.37.2" "1.38.0")
        KURL_VERSIONS_JS="$TEST_DIR/versions.js" update_available_versions 2>&1 && echo "rc=0" || echo "rc=$?"
    )"
    assertContains "$result" "cron-kubernetes-update-138' marker"
    assertContains "$result" "rc=1"
    local unchanged=
    same_content "$TEST_DIR/versions.js.orig" "$TEST_DIR/versions.js" && unchanged=0 || unchanged=1
    assertEquals "versions.js should be unchanged" "0" "$unchanged"
}

function test_main_fails_before_generating_when_marker_is_missing() {
    touch "$TEST_DIR/template/Dockerfile.137"
    write_versions_js_fixture "$TEST_DIR/versions.js"

    local result=
    result="$(
        export TEST_DIR
        KURL_TEMPLATE_DIR="$TEST_DIR/template" KURL_VERSIONS_JS="$TEST_DIR/versions.js" \
            bash -c '. "$1"; function generate_version_directory() { touch "$TEST_DIR/generated"; }; main 1.38.0' _ \
            "$ORIG_DIR/packages/kubernetes/template/script.sh" >/dev/null 2>&1 && echo "rc=0" || echo "rc=$?"
    )"
    assertNotEquals "rc=0" "$result"
    local generated=
    [ -e "$TEST_DIR/generated" ] && generated=0 || generated=1
    assertEquals "nothing should be generated" "1" "$generated"
}

function test_update_available_versions_does_not_confuse_patch_prefixes() {
    touch "$TEST_DIR/template/Dockerfile.137"
    write_versions_js_fixture "$TEST_DIR/versions.js"
    sed -i 's/"1.37.1",/"1.37.10",/' "$TEST_DIR/versions.js"

    must_cd "$TEST_DIR/template" || return 1
    VERSIONS=("1.37.1")
    KURL_VERSIONS_JS="$TEST_DIR/versions.js" update_available_versions
    must_cd "$ORIG_DIR" || return 1
    assertEquals "1" "$(grep -c '"1.37.1",' "$TEST_DIR/versions.js")"
    assertEquals "1" "$(grep -c '"1.37.10",' "$TEST_DIR/versions.js")"
}

function test_update_available_versions_supports_a_new_minor_marker() {
    touch "$TEST_DIR/template/Dockerfile.137" "$TEST_DIR/template/Dockerfile.138"
    write_versions_js_fixture "$TEST_DIR/versions.js"
    sed -i '/"1.36.4",/a\    // cron-kubernetes-update-138' "$TEST_DIR/versions.js"

    must_cd "$TEST_DIR/template" || return 1
    VERSIONS=("1.38.0")
    KURL_VERSIONS_JS="$TEST_DIR/versions.js" update_available_versions
    must_cd "$ORIG_DIR" || return 1
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
        elif [ -n "${FAIL_CHECKSUM_FETCH:-}" ]; then
            return 22
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
    local exists=
    [ -e "$TEST_DIR/kubeadm" ] && exists=0 || exists=1
    assertEquals "unverified kubeadm should be removed" "1" "$exists"
}

function test_download_kubeadm_reports_checksum_fetch_failure() {
    local result=
    result="$(
        FAIL_CHECKSUM_FETCH=1
        stub_curl_for_download
        download_kubeadm 1.38.0 "$TEST_DIR" 2>&1 && echo "rc=0" || echo "rc=$?"
    )"
    assertContains "$result" "failed to fetch the kubeadm v1.38.0 checksum"
    assertContains "$result" "curl exit 22"
    assertNotContains "$result" "invalid sha256"
    assertContains "$result" "rc=1"
    local exists=
    [ -e "$TEST_DIR/kubeadm" ] && exists=0 || exists=1
    assertEquals "unverified kubeadm should be removed" "1" "$exists"
}

# stub_generate_deps replaces the network calls of generate_version_directory. The fake kubeadm
# prints $FAKE_IMAGES and fails if it can see GITHUB_TOKEN or AWS_SECRET_ACCESS_KEY. Both FAKE_
# variables are baked in when the stub is written (kubeadm runs with an empty environment).
function stub_generate_deps() {
    function download_kubeadm() {
        cat > "$2/kubeadm" <<EOF
#!/bin/bash
if [ -n "\${GITHUB_TOKEN:-}\${AWS_SECRET_ACCESS_KEY:-}" ]; then echo "credential leaked to kubeadm" >&2; exit 1; fi
if [ -n "${FAKE_KUBEADM_FAIL:-}" ]; then exit 3; fi
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
        must_cd "$TEST_DIR/template" || return 1
        export GITHUB_TOKEN="secret" AWS_SECRET_ACCESS_KEY="secret"
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
    assertEquals "no staged Manifest left behind" "" "$(find "$TEST_DIR/1.38.0" -name '.Manifest.*')"
}

function test_generate_version_directory_keeps_old_manifest_on_kubeadm_failure() {
    mkdir -p "$TEST_DIR/1.38.0"
    echo "old" > "$TEST_DIR/1.38.0/Manifest"

    local result=
    result="$(
        must_cd "$TEST_DIR/template" || return 1
        FAKE_KUBEADM_FAIL=1
        FAKE_IMAGES='registry.k8s.io/kube-apiserver:v1.38.0\n'
        stub_generate_deps
        generate_version_directory 1.38.0 2>&1 && echo "rc=0" || echo "rc=$?"
    )"
    assertContains "$result" "kubeadm config images list failed for 1.38.0 (exit 3)"
    assertEquals "rc=1" "${result##*$'\n'}"
    assertEquals "old" "$(cat "$TEST_DIR/1.38.0/Manifest")"
}

function test_generate_version_directory_fails_without_images() {
    local result=
    result="$(
        must_cd "$TEST_DIR/template" || return 1
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
        must_cd "$TEST_DIR/template" || return 1
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
        must_cd "$TEST_DIR/template" || return 1
        function docker() { echo registry.k8s.io/e2e-test-images/agnhost:2.53; }
        generate_conformance_package 1.38.0 2>&1 && echo "rc=0" || echo "rc=$?"
    )"
    assertContains "$result" "no nginx image"
    assertContains "$result" "rc=1"
    local exists=
    [ -e "$TEST_DIR/1.38.0/conformance/Manifest" ] && exists=0 || exists=1
    assertEquals "no conformance Manifest should be written" "1" "$exists"
}

function test_generate_conformance_package_reports_docker_run_failure() {
    local result=
    result="$(
        must_cd "$TEST_DIR/template" || return 1
        function docker() { echo "manifest unknown" >&2; return 125; }
        generate_conformance_package 1.38.0 2>&1 && echo "rc=0" || echo "rc=$?"
    )"
    assertContains "$result" "listing conformance images failed (docker run registry.k8s.io/conformance:v1.38.0, exit 125)"
    assertEquals "rc=1" "${result##*$'\n'}"
    local exists=
    [ -e "$TEST_DIR/1.38.0/conformance/Manifest" ] && exists=0 || exists=1
    assertEquals "no conformance Manifest should be written" "1" "$exists"
}

# stub_docker_for_find stands in for docker in find_available_versions: build records the image tag
# in $TEST_DIR/built, run lists kubelet 1.<minor>.1 and 1.<minor>.2 for the k8s1<minor> image argument;
# run fails for the image named in FAIL_RUN and lists nothing for the one in EMPTY_RUN
function stub_docker_for_find() {
    function docker() {
        case "$1" in
            build) cat > /dev/null; echo "$3" >> "$TEST_DIR/built"; [ "$3" != "${FAIL_BUILD:-}" ] ;;
            run)
                local m=; m="$(printf '%s\n' "$@" | sed -n 's/^k8s1//p')"
                [ "k8s1$m" != "${FAIL_RUN:-}" ] || { echo "docker: no space left on device" >&2; return 125; }
                [ "k8s1$m" != "${EMPTY_RUN:-}" ] || return 0
                printf '%s\n' "kubelet/unknown 1.${m}.1-1.1 amd64" "kubelet/unknown 1.${m}.2-1.1 amd64" ;;
        esac
    }
}

function test_find_available_versions_skips_minor_not_in_versions_js() {
    touch "$TEST_DIR/template/Dockerfile.136" "$TEST_DIR/template/Dockerfile.137" "$TEST_DIR/template/Dockerfile.138"
    write_versions_js_fixture "$TEST_DIR/versions.js"
    # scaffolded by add-minor.sh: marker, no 1.38.x entry yet; a 1.38 version in another add-on doesn't count
    sed -i '/"1.36.4",/a\    // cron-kubernetes-update-138' "$TEST_DIR/versions.js"
    sed -i '/"0.27.4",/a\    "1.38.0",' "$TEST_DIR/versions.js"

    local result=
    result="$(
        must_cd "$TEST_DIR/template" || return 1
        stub_docker_for_find
        VERSIONS=()
        KURL_VERSIONS_JS="$TEST_DIR/versions.js" find_available_versions > "$TEST_DIR/stdout"
        echo "${VERSIONS[*]}"
    )"
    assertEquals "1.37.2 1.36.2" "$result"
    assertEquals "k8s137 k8s136" "$(xargs < "$TEST_DIR/built")"
    assertContains "$(cat "$TEST_DIR/stdout")" "Kubernetes 1.38 is not listed in versions.js yet, skipping"
}

function test_find_available_versions_fails_when_a_listed_minor_build_fails() {
    touch "$TEST_DIR/template/Dockerfile.136" "$TEST_DIR/template/Dockerfile.137"
    write_versions_js_fixture "$TEST_DIR/versions.js"

    local result=
    result="$(
        must_cd "$TEST_DIR/template" || return 1
        export TEST_DIR
        export -f stub_docker_for_find
        # a separate bash with script.sh's errexit on, as when script.sh runs for real
        FAIL_BUILD=k8s137 KURL_VERSIONS_JS="$TEST_DIR/versions.js" \
            bash -c '. "$1"; stub_docker_for_find; find_available_versions; echo "after build failure"' _ \
            "$ORIG_DIR/packages/kubernetes/template/script.sh" >/dev/null 2>&1 && echo "rc=0" || echo "rc=$?"
    )"
    assertNotEquals "rc=0" "$result"
    assertEquals "k8s137" "$(xargs < "$TEST_DIR/built")"
}

function test_find_available_versions_fails_when_listing_versions_fails() {
    touch "$TEST_DIR/template/Dockerfile.136" "$TEST_DIR/template/Dockerfile.137"
    write_versions_js_fixture "$TEST_DIR/versions.js"

    local result=
    result="$(
        must_cd "$TEST_DIR/template" || return 1
        stub_docker_for_find
        FAIL_RUN=k8s137 KURL_VERSIONS_JS="$TEST_DIR/versions.js" find_available_versions 2>&1 && echo "rc=0" || echo "rc=$?"
    )"
    assertContains "$result" "listing kubelet versions for Kubernetes 1.37 failed"
    assertContains "$result" "exit 125"
    assertContains "$result" "no space left on device"
    assertEquals "rc=1" "${result##*$'\n'}"
}

function test_find_available_versions_fails_when_no_versions_are_listed() {
    touch "$TEST_DIR/template/Dockerfile.136" "$TEST_DIR/template/Dockerfile.137"
    write_versions_js_fixture "$TEST_DIR/versions.js"

    local result=
    result="$(
        must_cd "$TEST_DIR/template" || return 1
        stub_docker_for_find
        EMPTY_RUN=k8s136 KURL_VERSIONS_JS="$TEST_DIR/versions.js" find_available_versions 2>&1 && echo "rc=0" || echo "rc=$?"
    )"
    assertContains "$result" "no kubelet 1.36.x versions found"
    assertEquals "rc=1" "${result##*$'\n'}"
}

function test_find_available_versions_fails_in_process_when_a_listed_minor_build_fails() {
    touch "$TEST_DIR/template/Dockerfile.136" "$TEST_DIR/template/Dockerfile.137"
    write_versions_js_fixture "$TEST_DIR/versions.js"

    local result=
    result="$(
        must_cd "$TEST_DIR/template" || return 1
        stub_docker_for_find
        FAIL_BUILD=k8s137 KURL_VERSIONS_JS="$TEST_DIR/versions.js" find_available_versions 2>&1 && echo "rc=0" || echo "rc=$?"
    )"
    assertContains "$result" "building the Kubernetes 1.37 package image failed"
    assertEquals "rc=1" "${result##*$'\n'}"
}

function test_find_available_versions_fails_when_the_kubernetes_array_is_not_found() {
    touch "$TEST_DIR/template/Dockerfile.137"
    write_versions_js_fixture "$TEST_DIR/versions.js"
    # versions.js changed shape: the array is no longer "kubernetes: ["
    sed -i 's/^  kubernetes: \[/  "kubernetes": [/' "$TEST_DIR/versions.js"

    local result=
    result="$(
        must_cd "$TEST_DIR/template" || return 1
        stub_docker_for_find
        KURL_VERSIONS_JS="$TEST_DIR/versions.js" find_available_versions 2>&1 && echo "rc=0" || echo "rc=$?"
    )"
    assertContains "$result" "no kubernetes versions found in the kubernetes array"
    assertNotContains "$result" "not listed in versions.js yet"
    assertEquals "rc=1" "${result##*$'\n'}"
    local built=
    [ -e "$TEST_DIR/built" ] && built=0 || built=1
    assertEquals "nothing should be built" "1" "$built"
}

function test_find_available_versions_fails_without_versions_js() {
    touch "$TEST_DIR/template/Dockerfile.137"

    local result=
    result="$(
        must_cd "$TEST_DIR/template" || return 1
        stub_docker_for_find
        KURL_VERSIONS_JS="$TEST_DIR/missing.js" find_available_versions 2>&1 && echo "rc=0" || echo "rc=$?"
    )"
    assertContains "$result" "versions.js not found"
    assertNotEquals "rc=0" "${result##*$'\n'}"
}

function test_main_works_without_github_output_from_any_cwd() {
    touch "$TEST_DIR/template/Dockerfile.137"
    write_versions_js_fixture "$TEST_DIR/versions.js"

    local result=
    result="$(
        must_cd / || return 1
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
