#!/bin/bash

set -e

mkdir -p /.ssh
ssh-keygen -t rsa -b 2048 -C "aka" -q -f /.ssh/id_rsa -N ""

cd /test/gcp
terraform apply -input=false
