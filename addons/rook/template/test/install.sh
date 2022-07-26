#!/bin/bash

. ./scripts/common/common.sh
. ./addons/rook/template/base/install.sh

function test_rook_should_skip_rook_install() {
    assertEquals 'rook_should_skip_rook_install "1.0.4" "1.6.11"' "Rook 1.0.4 is already installed, will not upgrade to 1.6.11" "$(rook_should_skip_rook_install "1.0.4" "1.6.11")"
    assertEquals 'rook_should_skip_rook_install "1.0.4" "1.6.11"' "0" "$(rook_should_skip_rook_install "1.0.4" "1.6.11" >/dev/null; echo $?)"
    assertEquals 'rook_should_skip_rook_install "1.4.3" "1.6.11"' "Rook 1.4.3 is already installed, will not upgrade to 1.6.11" "$(rook_should_skip_rook_install "1.4.3" "1.6.11")"
    assertEquals 'rook_should_skip_rook_install "1.4.3" "1.6.11"' "0" "$(rook_should_skip_rook_install "1.4.3" "1.6.11" >/dev/null; echo $?)"
    assertEquals 'rook_should_skip_rook_install "1.5.10" "1.6.11"' "" "$(rook_should_skip_rook_install "1.5.10" "1.6.11")"
    assertEquals 'rook_should_skip_rook_install "1.5.10" "1.6.11"' "1" "$(rook_should_skip_rook_install "1.5.10" "1.6.11" >/dev/null; echo $?)"
    assertEquals 'rook_should_skip_rook_install "1.5.12" "1.5.10"' "Rook 1.5.12 is already installed, will not downgrade to 1.5.10" "$(rook_should_skip_rook_install "1.5.12" "1.5.10")"
    assertEquals 'rook_should_skip_rook_install "1.5.12" "1.5.10"' "0" "$(rook_should_skip_rook_install "1.5.12" "1.5.10" >/dev/null; echo $?)"
    assertEquals 'rook_should_skip_rook_install "1.6.11" "1.4.3"' "Rook 1.6.11 is already installed, will not downgrade to 1.4.3" "$(rook_should_skip_rook_install "1.6.11" "1.4.3")"
    assertEquals 'rook_should_skip_rook_install "1.6.11" "1.4.3"' "0" "$(rook_should_skip_rook_install "1.6.11" "1.4.3" >/dev/null; echo $?)"
}

function test_rook_should_auth_allow_insecure_global_id_reclaim() {
    assertEquals 'rook_should_auth_allow_insecure_global_id_reclaim ""' "0" "$(rook_should_auth_allow_insecure_global_id_reclaim "" >/dev/null; echo $?)"
    assertEquals 'rook_should_auth_allow_insecure_global_id_reclaim "16.2.0"' "0" "$(rook_should_auth_allow_insecure_global_id_reclaim "16.2.0" >/dev/null; echo $?)"
    assertEquals 'rook_should_auth_allow_insecure_global_id_reclaim "16.2.1"' "1" "$(rook_should_auth_allow_insecure_global_id_reclaim "16.2.1" >/dev/null; echo $?)"
    assertEquals 'rook_should_auth_allow_insecure_global_id_reclaim "15.2.10"' "0" "$(rook_should_auth_allow_insecure_global_id_reclaim "15.2.10" >/dev/null; echo $?)"
    assertEquals 'rook_should_auth_allow_insecure_global_id_reclaim "15.2.11"' "1" "$(rook_should_auth_allow_insecure_global_id_reclaim "15.2.11" >/dev/null; echo $?)"
    assertEquals 'rook_should_auth_allow_insecure_global_id_reclaim "14.2.19"' "0" "$(rook_should_auth_allow_insecure_global_id_reclaim "14.2.19" >/dev/null; echo $?)"
    assertEquals 'rook_should_auth_allow_insecure_global_id_reclaim "14.2.20"' "1" "$(rook_should_auth_allow_insecure_global_id_reclaim "14.2.20" >/dev/null; echo $?)"
}

. shunit2
