#!/bin/bash

set -euo pipefail

RED=$'\033[0;31m'
NC=$'\033[0m' # No Color

IMAGE=
WHITELIST=

function main() {
    local file=
    local fail=

    file="$(mktemp --suffix=-vuln.csv)"

    grype -ojson "$IMAGE" \
        | jq -r '.matches[] | select(.vulnerability.fixedInVersion != null)
                | select(.vulnerability.severity == "Medium" or .vulnerability.severity == "High" or .vulnerability.severity == "Critical")
                | [.artifact.name, .artifact.version, .vulnerability.fixedInVersion, .vulnerability.id, .vulnerability.severity] | join(",")' \
        > "$file"

    if [ -s "$file" ]; then
        (printf "NAME,VERSION,FIX_VERSION,VULNERABILITY,SEVERITY\n" && cat "$file") | \
        awk 'BEGIN { FS = "," ; OFS = "\t" ; ORS = "\n" } ; { $1=$1 ; print $0 }'
        if [ -z "$WHITELIST" ]; then
            fail=1
        elif grep -qEv "$WHITELIST" "$file" ; then
            fail=1
        fi
    fi

    rm "$file"

    if [ "$fail" = "1" ]; then
        printf "%sdiscovered vulnerabilities at or above the severity threshold%s\n" "${RED}" "${NC}" 1>&2
        exit 1
    fi
}

function parse_argv() {
    IMAGE=$1
    WHITELIST=${2-}
    if [ -n "$WHITELIST" ]; then
        echo "Whitelist: $WHITELIST" 1>&2
    fi
}

parse_argv "$@"
main
