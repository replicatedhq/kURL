#!/bin/bash

. ./install_scripts/templates/common/cli-script.sh

testInstallCliFile()
{
    tmpDir="$(mktemp -d)"
    _installCliFile "$tmpDir" "echo" "CONTAINER"

    assertEquals "-i CONTAINER replicated COMMAND -ARG" "$("$tmpDir/replicated" -i COMMAND -ARG)"
    assertEquals "-i CONTAINER replicatedctl COMMAND -ARG" "$("$tmpDir/replicatedctl" -i COMMAND -ARG)"
    assertEquals "-t CONTAINER replicated COMMAND -ARG" "$("$tmpDir/replicated" -t COMMAND -ARG)"
    assertEquals "-t CONTAINER replicatedctl COMMAND -ARG" "$("$tmpDir/replicatedctl" -t COMMAND -ARG)"
    assertEquals "-it CONTAINER replicated COMMAND -ARG" "$("$tmpDir/replicated" -it COMMAND -ARG)"
    assertEquals "-it CONTAINER replicatedctl COMMAND -ARG" "$("$tmpDir/replicatedctl" -it COMMAND -ARG)"
    assertEquals "-it CONTAINER replicated COMMAND -ARG" "$("$tmpDir/replicated" -ti COMMAND -ARG)"
    assertEquals "-it CONTAINER replicatedctl COMMAND -ARG" "$("$tmpDir/replicatedctl" -ti COMMAND -ARG)"
    assertEquals "-it CONTAINER replicated COMMAND -ARG" "$("$tmpDir/replicated" --interactive --tty COMMAND -ARG)"
    assertEquals "-it CONTAINER replicatedctl COMMAND -ARG" "$("$tmpDir/replicatedctl" --interactive --tty COMMAND -ARG)"
    assertEquals "CONTAINER replicated COMMAND -ARG" "$("$tmpDir/replicated" --interactive=0 COMMAND -ARG)"
    assertEquals "CONTAINER replicatedctl COMMAND -ARG" "$("$tmpDir/replicatedctl" --interactive=0 COMMAND -ARG)"
    assertEquals "CONTAINER replicated COMMAND -ARG" "$("$tmpDir/replicated" --tty=0 COMMAND -ARG)"
    assertEquals "CONTAINER replicatedctl COMMAND -ARG" "$("$tmpDir/replicatedctl" --tty=0 COMMAND -ARG)"
    assertEquals "-t CONTAINER replicated COMMAND -ARG" "$("$tmpDir/replicated" --interactive=0 --tty=1 COMMAND -ARG)"
    assertEquals "-t CONTAINER replicatedctl COMMAND -ARG" "$("$tmpDir/replicatedctl" --interactive=0 --tty=1 COMMAND -ARG)"
}

testInstallCliFileAutodetect()
{
    tmpDir="$(mktemp -d)"
    _installCliFile "$tmpDir" "echo" "CONTAINER"

    if [ -t 0 ]; then
        assertEquals "-it CONTAINER replicatedctl COMMAND -ARG" "$("$tmpDir/replicatedctl" COMMAND -ARG)"
    elif [ -t 1 ]; then
        assertEquals "-i CONTAINER replicatedctl COMMAND -ARG" "$("$tmpDir/replicatedctl" COMMAND -ARG)"
    else
        assertEquals "CONTAINER replicatedctl COMMAND -ARG" "$("$tmpDir/replicatedctl" COMMAND -ARG)"
    fi
}

testInstallCliFileShellalias()
{
    tmpDir="$(mktemp -d)"
    _installCliFile "$tmpDir" "echo" "CONTAINER"

    # shell allias will alias "mycli" -> "replicated admin" so -it flags must come after "admin" command
    # also we do not want to force order of flags to replicated admin command
    assertEquals "-it CONTAINER replicated admin --no-tty --help -h COMMAND -ARG" "$("$tmpDir/replicated" admin --interactive --no-tty --help -h -t COMMAND -ARG)"
    assertEquals "-t CONTAINER replicated admin COMMAND -ARG" "$("$tmpDir/replicated" admin -t COMMAND -ARG)"
    assertEquals "CONTAINER replicated admin --no-tty COMMAND -ARG" "$("$tmpDir/replicated" admin --tty=0 COMMAND -ARG)"
    assertEquals "-i CONTAINER replicated admin --no-tty COMMAND -ARG" "$("$tmpDir/replicated" admin -i COMMAND -ARG)"
}

testInstallCliFileQuoteArgs()
{
    tmpDir="$(mktemp -d)"
    _installCliFile "$tmpDir" "echo" "CONTAINER"

    assertEquals "-i CONTAINER replicatedctl COMMAND -c echo hi" "$("$tmpDir/replicatedctl" -i COMMAND -c "echo hi")"
}

. shunit2
