#!/bin/bash

set -euo pipefail

function log() {
    echo "$1" 1>&2
}

function bail() {
    log "$1"
    exit 1
}

function require() {
    if [ -z "$2" ]; then
        echo "validation failed: $1 unset"
        exit 1
    fi
}

require STAGING_RELEASE "${STAGING_RELEASE}"

function main() {
  local testgrid_run_json
  testgrid_run_json=$(curl -s "https://api.testgrid.kurl.sh/api/v1/runs?searchRef=${STAGING_RELEASE}")

  # TG-API is broken. We should never find more than one test run for a staging release
  # associated with a particular GIT commit SHA.
  if echo "${testgrid_run_json}" | jq -e '.total > 1' &>/dev/null; then
    bail "TG-API returned multiple testgrid runs: ${testgrid_run_json}\nDid testgrid list runs api break?"
  fi

  # check if run exist
  if echo "${testgrid_run_json}" | jq -e '.total == 0' &>/dev/null; then
    bail "Did not find testgrid run for release ${STAGING_RELEASE}"
  fi

  local run_id
  local success_count
  local failure_count
  local total_runs
  local unsupported_count
  local skipped_count
  run_id=$(echo "${testgrid_run_json}" | jq -r '.runs[].id')
  success_count=$(echo "${testgrid_run_json}" | jq -r '.runs[].success_count')
  failure_count=$(echo "${testgrid_run_json}" | jq -r '.runs[].failure_count')
  total_runs=$(echo "${testgrid_run_json}" | jq -r '.runs[].total_runs')

  log "Found Testgrid run: https://testgrid.kurl.sh/run/${run_id}"
  log "Testgrid run details:"
  echo "${testgrid_run_json}" | jq

  # determine the number of test instances that were unsupported and skipped for the test run
  unsupported_count=$(curl -d {} -s "https://api.testgrid.kurl.sh/api/v1/run/${run_id}" | jq '.instances[].isUnsupported' | grep -c true || true)
  skipped_count=$(curl -d {} -s "https://api.testgrid.kurl.sh/api/v1/run/${run_id}" | jq '.instances[].isSkipped' | grep -c true || true)

  if [[ $((success_count + failure_count + unsupported_count + skipped_count)) -ne ${total_runs} ]]; then
    bail "Testgrid run ${run_id} seems to have pending runs"
  fi
}

main "$@"
