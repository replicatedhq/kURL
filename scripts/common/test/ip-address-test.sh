#!/bin/bash

. ./install_scripts/templates/common/ip-address.sh

testIsValidIpv6()
{
    assertEquals "ipv6 full" "0" "$(isValidIpv6 "FE80:CD00:0000:0CDE:1257:0000:211E:729C"; echo $?)"
    assertEquals "ipv6 short" "0" "$(isValidIpv6 "FE80:CD00:0:CDE:1257:0:211E:729C"; echo $?)"
    assertEquals "ipv6 loopback" "0" "$(isValidIpv6 "::1"; echo $?)"
    assertEquals "ipv6 full brackets" "1" "$(isValidIpv6 "[FE80:CD00:0000:0CDE:1257:0000:211E:729C]"; echo $?)"
    assertEquals "ipv6 short brackets" "1" "$(isValidIpv6 "[FE80:CD00:0:CDE:1257:0:211E:729C]"; echo $?)"
    assertEquals "ipv6 loopback brackets" "1" "$(isValidIpv6 "[::1]"; echo $?)"
    assertEquals "ipv4" "1" "$(isValidIpv6 "172.31.28.36"; echo $?)"
    assertEquals "ipv4 loopback" "1" "$(isValidIpv6 "127.17.0.1"; echo $?)"
    assertEquals "domain" "1" "$(isValidIpv6 "facebook.com"; echo $?)"
    assertEquals "localhost" "1" "$(isValidIpv6 "localhost"; echo $?)"
}

. shunit2
