#!/bin/bash

set -e

. ./scripts/common/proxy.sh

function test_unique_no_proxy_addresses() {
    assertEquals "basic" "a,b,c" "$(unique_no_proxy_addresses "a,b,b,a,c,a,b")"
    assertEquals "empty" "a,b,c" "$(unique_no_proxy_addresses "a,b,b, ,a,c,a, ,b")"
}

. shunit2
