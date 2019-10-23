#!/usr/bin/env bash

# This script uses arg $1 (name of *.jsonnet file to use) to generate the manifests/*.yaml files.

set -e
set -x
# Only exit with zero if all commands of the pipeline exit successfully
set -o pipefail

# Make sure to start with a clean 'manifests' dir
rm -rf manifests
mkdir manifests

jb update

# We would like to generate yaml, not json
jsonnet -J vendor -m manifests prometheus.jsonnet | xargs -I{} sh -c 'cat {} | gojsontoyaml > {}.yaml; rm -f {}' -- {}

find ../operator/ ! -name 'kustomization.yaml' -maxdepth 1 -type f -exec rm -f {} +
mv manifests/0* ../operator/
find ../grafana/ ! -name 'kustomization.yaml' -maxdepth 1 -type f -exec rm -f {} +
mv manifests/grafana-* ../grafana/
find ../monitors/ ! -name 'kustomization.yaml' -maxdepth 1 -type f -exec rm -f {} +
mv manifests/* ../monitors/
cp ../operator/0prometheus-operator-serviceMonitor.yaml ../monitors/

rm -rf manifests
