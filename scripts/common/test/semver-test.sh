#!/bin/bash

. ./install_scripts/templates/common/common.sh

testParseSemver()
{
    semverParse "2.29.1"
    assertEquals "Major not equal" "2" "$major"
    assertEquals "Minor not equal" "29" "$minor"
    assertEquals "Patch not equal" "1" "$patch"
}

testCompareSemverEq()
{
    semverCompare "2.29.1" "2.29.1"
    assertEquals "Semver eq comparison failed 2.29.1 2.29.1" "0" "$SEMVER_COMPARE_RESULT"
}

testCompareSemverLt()
{
    semverCompare "2.28.0" "2.29.1"
    assertEquals "Semver lt comparison failed 2.28.0 2.29.1" "-1" "$SEMVER_COMPARE_RESULT"

    semverCompare "2.29.0" "2.29.1"
    assertEquals "Semver lt comparison failed 2.29.0 2.29.1" "-1" "$SEMVER_COMPARE_RESULT"
}

testCompareSemverGt()
{
    semverCompare "2.29.1" "2.28.0"
    assertEquals "Semver gt comparison failed 2.29.1 2.28.0" "1" "$SEMVER_COMPARE_RESULT"

    semverCompare "2.29.1" "2.29.0"
    assertEquals "Semver gt comparison failed 2.29.1 2.29.0" "1" "$SEMVER_COMPARE_RESULT"
}

. shunit2
