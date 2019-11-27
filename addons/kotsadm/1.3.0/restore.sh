#!/bin/bash

set -e

if [ ! -f /backups/db.dump ]; then
    exit 0
fi

pg_restore --dbname "$POSTGRES_URI"

rm /backups/db.dump
