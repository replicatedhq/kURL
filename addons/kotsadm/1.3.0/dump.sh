#!/bin/bash

set -e

pg_dump --dbname $POSTGRES_URI --file /backups/db.dump
