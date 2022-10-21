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

. shunit2
