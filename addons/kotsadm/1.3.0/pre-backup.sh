#!/bin/bash

set -e

pg_dump --dbname $POSTGRES_URI --file /backups/db.dump

S3_ACCESS_KEY=$S3_ACCESS_KEY_ID S3_SECRET_KEY=$S3_SECRET_ACCESS_KEY s4cmd --endpoint-url=$S3_ENDPOINT dsync -r s3://kotsadm/ /backups/s3
