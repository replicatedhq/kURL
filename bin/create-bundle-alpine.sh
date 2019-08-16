#!/bin/sh

set -eo pipefail

apk add curl

SIGNED_PUT_URL="$1"
shift

mkdir -p /tmp/work
cd /tmp/work

while [ -n "$1" ]; do
    echo "Downloading and extracting $1"
    curl -L "$1" | tar zxf -
    shift
done

# TODO redact
echo "Uploading $SIGNED_PUT_URL"
tar cf - . | gzip | curl -X POST -d @- "$SIGNED_PUT_URL"

# TODO remove sleep
sleep 3600
exit 0
