#!/bin/bash

set -e

if [ ! -f /backups/db.dump ]; then
    exit 0
fi

psgl "$POSTGRES_URI" < /backups/db.dump

rm /backups/db.dump
