#!/bin/bash

# retry <retries> <command...>
#
# Exponential-backoff retry for flaky network calls. Shared by
# bin/retag-and-push-kurl-util-image.sh; mirrors the S3 retry helpers
# inlined in testgrid-pr.yaml's copy-packages/build-and-upload jobs.
function retry() {
    local retries="$1"; shift
    local count=0 exit wait
    until "$@"; do
        exit=$?
        wait=$((2 ** count))
        count=$((count + 1))
        if [ "${count}" -lt "${retries}" ]; then
            echo "Retry ${count}/${retries} exited ${exit}, retrying in ${wait}s..." >&2
            sleep "${wait}"
        else
            echo "Retry ${count}/${retries} exited ${exit}, no more retries left." >&2
            return "${exit}"
        fi
    done
    return 0
}
