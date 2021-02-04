#!/bin/bash

set -e

. ./scripts/common/common.sh

function test_get_kurl_install_directory_flag() {
    assertEquals "get_kurl_install_directory_flag default" "" "$(get_kurl_install_directory_flag /var/lib/kurl)"

    assertEquals "get_kurl_install_directory_flag KURL_INSTALL_DIRECTORY ." " kurl-install-directory=." "$(get_kurl_install_directory_flag .)"
}

. shunit2
