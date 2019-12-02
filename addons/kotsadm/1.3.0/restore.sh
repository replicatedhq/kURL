#!/bin/bash

set -e

restored_something=0

if [ -f /backups/db.dump ]; then
    echo "Restoring postgres..."
    psql "$POSTGRES_URI" < /backups/db.dump
    rm /backups/db.dump
    restored_something=1
fi

if [ -d /backups/s3 ]; then
    echo "Restoring S3..."
    S3_ACCESS_KEY=$S3_ACCESS_KEY_ID S3_SECRET_KEY=$S3_SECRET_ACCESS_KEY s4cmd --endpoint-url=$S3_ENDPOINT dsync -r /backups/s3 s3://kotsadm/
    rm -r /backups/s3
    restored_something=1
fi

if [ $restored_something = "0" ]; then
    echo "Nothing to restore"
fi
