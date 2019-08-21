#!/bin/sh

set -e

apk add curl

SIGNED_PUT_URL="$1"
shift

mkdir -p /tmp/work
cd /tmp/work

cp /scripts/install.sh /tmp/work/install.sh
cp /scripts/join.sh /tmp/work/join.sh

while [ -n "$1" ]; do
    echo "Downloading and extracting $1"
    curl -L "$1" | tar zxf -
    shift
done

cd /tmp
tar czf bundle.tar.gz -C work .
curl --upload-file bundle.tar.gz -H 'Content-Type: application/gzip' "$SIGNED_PUT_URL"
