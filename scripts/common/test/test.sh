#!/bin/bash

set -e

./tests_shell/cli-script-test.sh
./tests_shell/common-test.sh
./tests_shell/docker-version-test.sh
./tests_shell/ip-address-test.sh
./tests_shell/proxy-test.sh
./tests_shell/semver-test.sh
