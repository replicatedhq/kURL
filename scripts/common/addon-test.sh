#!/bin/bash

set -e

# shellcheck disable=SC1091
. ./scripts/common/common.sh
# shellcheck disable=SC1091
. ./scripts/common/prompts.sh

function test_addon_fetch_multiple_airgap() {
    # shellcheck disable=SC1091
    . ./scripts/common/addon.sh

    prompts_can_prompt() {
        # shellcheck disable=SC2317
        return 1
    }

    # shellcheck disable=SC2034
    local KURL_INSTALL_DIRECTORY=/var/lib/kurl
    # shellcheck disable=SC2034
    local KURL_URL="https://kurl.sh"
    # shellcheck disable=SC2034
    local KURL_VERSION="v0.0.0-0"
    # shellcheck disable=SC2034
    local INSTALLER_ID="1234"

    local expected="The following packages are not available locally, and are required:
    rook-1.tar.gz
    rook-2.tar.gz
    rook-3.tar.gz

You can download them with the following command:

    curl -LO https://kurl.sh/bundle/version/v0.0.0-0/1234/packages/rook-1,rook-2,rook-3.tar.gz

Please move this file to /var/lib/kurl/assets/rook-1,rook-2,rook-3.tar.gz before rerunning the installer."
    local addon_versions=( rook-1 rook-2 rook-3 )
    TEST_PROMPT_RESULT=""
    assertEquals "addon_fetch_multiple_airgap rook-1 rook-2 rook-3" "$expected" "$(addon_fetch_multiple_airgap "${addon_versions[@]}" 2>&1 | remove_colors)"
}

function test_addon_fetch_airgap_prompt_for_package_cant_prompt() {
    # shellcheck disable=SC1091
    . ./scripts/common/addon.sh

    # shellcheck disable=SC2034
    local KURL_INSTALL_DIRECTORY=/var/lib/kurl

    prompts_can_prompt() {
        # shellcheck disable=SC2317
        return 1
    }

    local expected="Please move this file to /var/lib/kurl/assets/rook-1.tar.gz before rerunning the installer."
    assertEquals "addon_fetch_airgap_prompt_for_package rook-1.tar.gz" "$expected" "$(addon_fetch_airgap_prompt_for_package rook-1.tar.gz 2>&1 | remove_colors)"
}

function test_addon_fetch_airgap_prompt_for_package_can_prompt() {
    # shellcheck disable=SC1091
    . ./scripts/common/addon.sh

    # shellcheck disable=SC2034
    local KURL_INSTALL_DIRECTORY=/var/lib/kurl

    prompts_can_prompt() {
        # shellcheck disable=SC2317
        return 0
    }

    local expected="Please provide the path to the file on the server.
Absolute path to file: Package rook-1.tar.gz not provided.
You can provide the path to this file the next time the installer is run,
or move it to /var/lib/kurl/assets/rook-1.tar.gz to be detected automatically."
    # shellcheck disable=SC2034
    local TEST_PROMPT_RESULT=""
    assertEquals "addon_fetch_airgap_prompt_for_package rook-1.tar.gz" "$expected" "$(addon_fetch_airgap_prompt_for_package rook-1.tar.gz 2>&1 | remove_colors)"
}

function remove_colors() {
    sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2};?)?)?[mGK]//g"
}

# shellcheck disable=SC1091
. shunit2
