#!/bin/bash

set -e

# shellcheck disable=SC1091
. ./scripts/common/common.sh
# shellcheck disable=SC1091
. ./scripts/common/docker.sh
# shellcheck disable=SC1091
. ./scripts/common/rook-upgrade.sh

function test_rook_upgrade_should_upgrade_rook() {
    assertEquals "1.0.4 to 1.4.9 should succeed" "0" "$(rook_upgrade_should_upgrade_rook "1.0.4" "1.4.9"; echo $?)"
    assertEquals "1.0.4-14.2.21 to 1.4.9 should succeed" "0" "$(rook_upgrade_should_upgrade_rook "1.0.4-14.2.21" "1.4.9"; echo $?)"
    assertEquals "1.0.4 to patch versions less than 1.4.9 should fail" "1" "$(rook_upgrade_should_upgrade_rook "1.0.4" "1.4.3"; echo $?)"
    assertEquals "failed upgrades on the way to 1.4.9 should succeed" "0" "$(rook_upgrade_should_upgrade_rook "1.3.11" "1.4.9"; echo $?)"
    assertEquals "1.0.4 to 1.7.11 should succeed" "0" "$(rook_upgrade_should_upgrade_rook "1.0.4" "1.7.11"; echo $?)"
    assertEquals "1.5.9 to 1.7.11 should succeed" "0" "$(rook_upgrade_should_upgrade_rook "1.5.9" "1.7.11"; echo $?)"
    assertEquals "1.5.9 to 1.5.12 should fail" "1" "$(rook_upgrade_should_upgrade_rook "1.5.9" "1.5.12"; echo $?)"
    assertEquals "1.5.9 to 1.6.11 should fail" "1" "$(rook_upgrade_should_upgrade_rook "1.5.9" "1.6.11"; echo $?)"
    assertEquals "1.5.9 to 1.7.11 should succeed" "0" "$(rook_upgrade_should_upgrade_rook "1.5.9" "1.7.11"; echo $?)"
    assertEquals "1.9.12 to 1.11.2 should succeed" "0" "$(rook_upgrade_should_upgrade_rook "1.9.12" "1.11.2"; echo $?)"
}

function test_rook_upgrade_list_rook_ceph_images_in_manifest_file() {
    assertEquals "docker.io/rook/ceph:v1.1.9 docker.io/rook/ceph:v1.2.7 docker.io/rook/ceph:v1.3.11 docker.io/rook/ceph:v1.4.9" "$(rook_upgrade_list_rook_ceph_images_in_manifest_file "./addons/rookupgrade/10to14/Manifest")"
    assertEquals "docker.io/rook/ceph:v1.9.12" "$(rook_upgrade_list_rook_ceph_images_in_manifest_file "./addons/rook/1.9.12/Manifest")"
}

function test_rook_upgrade_merge_images_list() {
    assertEquals "merges two lists" "docker.io/rook/ceph:v1.1.9 docker.io/rook/ceph:v1.2.7 docker.io/rook/ceph:v1.3.11 docker.io/rook/ceph:v1.4.9 docker.io/rook/ceph:v1.9.12" "$(rook_upgrade_merge_images_list "docker.io/rook/ceph:v1.1.9 docker.io/rook/ceph:v1.2.7 docker.io/rook/ceph:v1.3.11 docker.io/rook/ceph:v1.4.9" "docker.io/rook/ceph:v1.9.12")"
    assertEquals "trims spaces and removes duplicates" "a b c d" "$(rook_upgrade_merge_images_list " a   b  c d   " " b  d a c d")"
}

function test_rook_upgrade_compare_rook_versions() {
    assertEquals "1.4 is greater than 1.0" "1" "$(rook_upgrade_compare_rook_versions "1.4" "1.0")"
    assertEquals "1.0 is less than 1.4" "-1" "$(rook_upgrade_compare_rook_versions "1.0" "1.4")"
    assertEquals "1.0 is equal to 1.0" "0" "$(rook_upgrade_compare_rook_versions "1.0" "1.0")"
    assertEquals "2.1 is greater than 1.2" "1" "$(rook_upgrade_compare_rook_versions "2.1" "1.2")"
    assertEquals "1.2 is less than 2.1" "-1" "$(rook_upgrade_compare_rook_versions "1.2" "2.1")"
}

function test_rook_upgrade_max_rook_version() {
    assertEquals "1.0 or 1.1 should be 1.1" "1.1" "$(rook_upgrade_max_rook_version "1.0" "1.1")"
    assertEquals "1.1 or 1.0 should be 1.1" "1.1" "$(rook_upgrade_max_rook_version "1.1" "1.0")"
    assertEquals "1.0 or 2.0 should be 2.0" "2.0" "$(rook_upgrade_max_rook_version "1.0" "2.0")"
    assertEquals "1.0 or 1.0 should be 1.0" "1.0" "$(rook_upgrade_max_rook_version "1.0" "1.0")"
}

function test_rook_upgrade_is_version_included() {
    assertEquals "1.0 is included in 1.0 to 1.4" "1" "$(rook_upgrade_is_version_included "1.0" "1.4" "1.0"; echo $?)"
    assertEquals "1.1 is included in 1.0 to 1.4" "0" "$(rook_upgrade_is_version_included "1.0" "1.4" "1.1"; echo $?)"
    assertEquals "1.4 is included in 1.0 to 1.4" "0" "$(rook_upgrade_is_version_included "1.0" "1.4" "1.4"; echo $?)"
    assertEquals "1.5 is included in 1.0 to 1.4" "1" "$(rook_upgrade_is_version_included "1.0" "1.4" "1.5"; echo $?)"
}

function test_rook_upgrade_step_versions() {
    function echo_exit_code() {
        # shellcheck disable=SC2317
        echo "$?"
    }
    # shellcheck disable=SC2034
    local step_versions=(1.0.4-14.2.21 0.0.0 0.0.0 0.0.0 1.4.9 1.5.12 1.6.11 1.7.11 1.8.10 1.9.12 1.10.11 1.11.2)
    assertEquals "6 to 6" "1.6.11" "$(rook_upgrade_step_versions "step_versions[@]" "1.6" "1.6")"
    assertEquals "6 to 9" "$(echo -e "1.6.11\n1.7.11\n1.8.10\n1.9.12")" "$(rook_upgrade_step_versions "step_versions[@]" "1.6" "1.9")"
    assertEquals "0 to 2" "$(echo -e "1.0.4-14.2.21\n0.0.0\n0.0.0")" "$(rook_upgrade_step_versions "step_versions[@]" "1.0" "1.2")"
    assertEquals "9 to 11" "$(echo -e "1.9.12\n1.10.11\n1.11.2")" "$(rook_upgrade_step_versions "step_versions[@]" "1.9" "1.11")"
    assertEquals "9 to 15" "1" "$(trap "echo_exit_code" EXIT; rook_upgrade_step_versions "step_versions[@]" "1.9" "1.15"; trap '' EXIT)"
    assertEquals "6 to 4" "" "$(rook_upgrade_step_versions "step_versions[@]" "1.6" "1.4")"
}

function test_rook_upgrade_print_list_of_minor_upgrades() {
    assertEquals "10 to 11" "This involves upgrading from 1.0.x to 1.1." "$(rook_upgrade_print_list_of_minor_upgrades "1.0" "1.1")"
    assertEquals "10 to 14" "This involves upgrading from 1.0.x to 1.1, 1.1 to 1.2, 1.2 to 1.3, and 1.3 to 1.4." "$(rook_upgrade_print_list_of_minor_upgrades "1.0" "1.4")"
}

function test_rook_upgrade_major_minor_to_major() {
    assertEquals "1.0 to 1" "1" "$(rook_upgrade_major_minor_to_major "1.0")"
    assertEquals "1.2 to 1" "1" "$(rook_upgrade_major_minor_to_major "1.2")"
    assertEquals "1.2.3 to 1" "1" "$(rook_upgrade_major_minor_to_major "1.2")"
    assertEquals "12.2 to 12" "12" "$(rook_upgrade_major_minor_to_major "12.2")"
}

function test_rook_upgrade_major_minor_to_minor() {
    assertEquals "1.0 to 0" "0" "$(rook_upgrade_major_minor_to_minor "1.0")"
    assertEquals "1.2 to 2" "2" "$(rook_upgrade_major_minor_to_minor "1.2")"
    assertEquals "1.2.3 to 2" "2" "$(rook_upgrade_major_minor_to_minor "1.2")"
    assertEquals "12.2 to 2" "2" "$(rook_upgrade_major_minor_to_minor "12.2")"
}

function test_rook_upgrade_rook_version_to_major_minor() {
    assertEquals "1.9.12 => 1.9" "1.9" "$(rook_upgrade_rook_version_to_major_minor "1.9.12")"
    assertEquals "1.0.4-14.2.21 => 1.0" "1.0" "$(rook_upgrade_rook_version_to_major_minor "1.0.4-14.2.21")"
}

function test_rook_upgrade_required_disk_space() {
    assertEquals "1.0 to 1.5" "6100" "$(rook_upgrade_required_archive_size "1.0" "1.5")"
    assertEquals "1.0 to 1.10" "14300" "$(rook_upgrade_required_archive_size "1.0" "1.10")"
    assertEquals "1.5 to 1.10" "8200" "$(rook_upgrade_required_archive_size "1.5" "1.10")"
    assertEquals "1.0 to 1.15" "24300" "$(rook_upgrade_required_archive_size "1.0" "1.15")"
}

# shellcheck disable=SC1091
. shunit2
