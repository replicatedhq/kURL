#!/bin/bash

. ./scripts/common/common.sh
. ./scripts/common/discover.sh

test_discover_public_ip()
{
    local ip_address=
    function curl() {
        echo "$ip_address"
    }
    export curl

    ip_address=172.31.28.36
    PUBLIC_ADDRESS=
    discover_public_ip
    assertEquals "172.31.28.36" "$PUBLIC_ADDRESS"

    ip_address=FE80:CD00:0:CDE:1257:0:211E:729C
    PUBLIC_ADDRESS=
    discover_public_ip
    assertEquals "FE80:CD00:0:CDE:1257:0:211E:729C" "$PUBLIC_ADDRESS"

    ip_address=invalid
    PUBLIC_ADDRESS=
    discover_public_ip
    assertEquals "" "$PUBLIC_ADDRESS"
}

. shunit2
