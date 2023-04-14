#!/bin/bash

set -e

. ./scripts/common/common.sh

function test_get_kurl_install_directory_flag() {
    assertEquals "get_kurl_install_directory_flag default" "" "$(get_kurl_install_directory_flag /var/lib/kurl)"

    assertEquals "get_kurl_install_directory_flag KURL_INSTALL_DIRECTORY ." " kurl-install-directory=." "$(get_kurl_install_directory_flag .)"
}

function test_package_download_url_with_retry() {
    local tmpdir="$(mktemp -d)"

    assertEquals "package_download_url_with_retry 404" "22" "$(package_download_url_with_retry "https://api.replicated.com/404" "${tmpdir}/fail" || echo $?)"
    assertEquals "package_download_url_with_retry success" "" "$(package_download_url_with_retry "https://kurl-sh.s3.amazonaws.com/dist/v2022.07.29-0/addons-gen.json" "${tmpdir}/success" "2" || echo $?)"

    rm -rf "$tmpdir"
}

function test_sleep_spinner() {
    assertEquals 'sleep_spinner 2' "0" "$(sleep_spinner 2 >/dev/null; echo $?)"
}

function test_canonical_image_name() {
    assertEquals "docker.io/library/image:1.0" "$(canonical_image_name "image:1.0")"
    assertEquals "docker.io/library/image:1.0" "$(canonical_image_name "library/image:1.0")"
    assertEquals "docker.io/library/image:1.0" "$(canonical_image_name "docker.io/library/image:1.0")"
    assertEquals "docker.io/org/image:1.0" "$(canonical_image_name "org/image:1.0")"
    assertEquals "docker.io/org/image:1.0" "$(canonical_image_name "docker.io/org/image:1.0")"
    assertEquals "quay.io/org/image:1.0" "$(canonical_image_name "quay.io/org/image:1.0")"
    assertEquals "docker.io/library/image:latest" "$(canonical_image_name "image")"
    assertEquals "docker.io/library/image:latest" "$(canonical_image_name "library/image")"
    assertEquals "docker.io/library/image:latest" "$(canonical_image_name "docker.io/library/image")"
    assertEquals "docker.io/library/image:latest" "$(canonical_image_name "docker.io/library/image:latest")"
    assertEquals "docker.io/org/image:latest" "$(canonical_image_name "org/image:latest")"
    assertEquals "quay.io/org/image:latest" "$(canonical_image_name "quay.io/org/image:latest")"
}

function test_common_upgrade_step_versions() {
    function echo_exit_code() {
        # shellcheck disable=SC2317
        echo "$?"
    }
    # shellcheck disable=SC2034
    local step_versions=(1.0.4-14.2.21 0.0.0 0.0.0 0.0.0 1.4.9 1.5.12 1.6.11 1.7.11 1.8.10 1.9.12 1.10.11 1.11.2)
    assertEquals "6 to 6" "" "$(common_upgrade_step_versions "${step_versions[*]}" "1.6" "1.6")"
    assertEquals "6 to 9" "$(echo -e "1.7.11\n1.8.10\n1.9.12")" "$(common_upgrade_step_versions "${step_versions[*]}" "1.6" "1.9")"
    assertEquals "0 to 2" "$(echo -e "0.0.0\n0.0.0")" "$(common_upgrade_step_versions "${step_versions[*]}" "1.0" "1.2")"
    assertEquals "9 to 11" "$(echo -e "1.10.11\n1.11.2")" "$(common_upgrade_step_versions "${step_versions[*]}" "1.9" "1.11")"
    assertEquals "9 to 15" "1" "$(trap "echo_exit_code" EXIT; common_upgrade_step_versions "${step_versions[*]}" "1.9" "1.15"; trap '' EXIT)"
    assertEquals "6 to 4" "" "$(common_upgrade_step_versions "${step_versions[*]}" "1.6" "1.4")"
}

function test_common_upgrade_major_minor_to_major() {
    assertEquals "1.0 to 1" "1" "$(common_upgrade_major_minor_to_major "1.0")"
    assertEquals "1.2 to 1" "1" "$(common_upgrade_major_minor_to_major "1.2")"
    assertEquals "1.2.3 to 1" "1" "$(common_upgrade_major_minor_to_major "1.2")"
    assertEquals "12.2 to 12" "12" "$(common_upgrade_major_minor_to_major "12.2")"
}

function test_common_upgrade_major_minor_to_minor() {
    assertEquals "1.0 to 0" "0" "$(common_upgrade_major_minor_to_minor "1.0")"
    assertEquals "1.2 to 2" "2" "$(common_upgrade_major_minor_to_minor "1.2")"
    assertEquals "1.2.3 to 2" "2" "$(common_upgrade_major_minor_to_minor "1.2")"
    assertEquals "12.2 to 2" "2" "$(common_upgrade_major_minor_to_minor "12.2")"
}

function test_common_upgrade_version_to_major_minor() {
    assertEquals "1.9.12 => 1.9" "1.9" "$(common_upgrade_version_to_major_minor "1.9.12")"
    assertEquals "1.0.4-14.2.21 => 1.0" "1.0" "$(common_upgrade_version_to_major_minor "1.0.4-14.2.21")"
}

function test_common_upgrade_compare_versions() {
    assertEquals "1.4 is greater than 1.0" "1" "$(common_upgrade_compare_versions "1.4" "1.0")"
    assertEquals "1.0 is less than 1.4" "-1" "$(common_upgrade_compare_versions "1.0" "1.4")"
    assertEquals "1.0 is equal to 1.0" "0" "$(common_upgrade_compare_versions "1.0" "1.0")"
    assertEquals "2.1 is greater than 1.2" "1" "$(common_upgrade_compare_versions "2.1" "1.2")"
    assertEquals "1.2 is less than 2.1" "-1" "$(common_upgrade_compare_versions "1.2" "2.1")"
}

function test_common_upgrade_max_version() {
    assertEquals "1.0 or 1.1 should be 1.1" "1.1" "$(common_upgrade_max_version "1.0" "1.1")"
    assertEquals "1.1 or 1.0 should be 1.1" "1.1" "$(common_upgrade_max_version "1.1" "1.0")"
    assertEquals "1.0 or 2.0 should be 2.0" "2.0" "$(common_upgrade_max_version "1.0" "2.0")"
    assertEquals "1.0 or 1.0 should be 1.0" "1.0" "$(common_upgrade_max_version "1.0" "1.0")"
}

function test_common_upgrade_is_version_included() {
    assertEquals "1.0 is included in 1.0 to 1.4" "1" "$(common_upgrade_is_version_included "1.0" "1.4" "1.0"; echo $?)"
    assertEquals "1.1 is included in 1.0 to 1.4" "0" "$(common_upgrade_is_version_included "1.0" "1.4" "1.1"; echo $?)"
    assertEquals "1.4 is included in 1.0 to 1.4" "0" "$(common_upgrade_is_version_included "1.0" "1.4" "1.4"; echo $?)"
    assertEquals "1.5 is included in 1.0 to 1.4" "1" "$(common_upgrade_is_version_included "1.0" "1.4" "1.5"; echo $?)"
}

function test_common_upgrade_print_list_of_minor_upgrades() {
    assertEquals "10 to 11" "This involves upgrading from 1.0.x to 1.1." "$(common_upgrade_print_list_of_minor_upgrades "1.0" "1.1")"
    assertEquals "10 to 14" "This involves upgrading from 1.0.x to 1.1, 1.1 to 1.2, 1.2 to 1.3, and 1.3 to 1.4." "$(common_upgrade_print_list_of_minor_upgrades "1.0" "1.4")"
}

function test_common_list_images_in_manifest_file() {
    assertEquals "registry.k8s.io/kube-apiserver:v1.26.3 registry.k8s.io/kube-controller-manager:v1.26.3 registry.k8s.io/kube-scheduler:v1.26.3 registry.k8s.io/kube-proxy:v1.26.3 registry.k8s.io/pause:3.9 registry.k8s.io/etcd:3.5.6-0 registry.k8s.io/coredns/coredns:v1.9.3" "$(common_list_images_in_manifest_file "./packages/kubernetes/1.26.3/Manifest")"
}

function test_common_upgrade_merge_images_list() {
    assertEquals "merges two lists" "docker.io/rook/ceph:v1.1.9 docker.io/rook/ceph:v1.2.7 docker.io/rook/ceph:v1.3.11 docker.io/rook/ceph:v1.4.9 docker.io/rook/ceph:v1.9.12" "$(common_upgrade_merge_images_list "docker.io/rook/ceph:v1.1.9 docker.io/rook/ceph:v1.2.7 docker.io/rook/ceph:v1.3.11 docker.io/rook/ceph:v1.4.9" "docker.io/rook/ceph:v1.9.12")"
    assertEquals "trims spaces and removes duplicates" "a b c d" "$(common_upgrade_merge_images_list " a   b  c d   " " b  d a c d")"
}

. shunit2
