#!/bin/bash

set -euo pipefail

function log() {
    echo "$1" 1>&2
}

function bail() {
    log "$1"
    exit 1
}

function main() {
  local testgrid_run_json
  testgrid_run_json=$(curl -s "https://api.testgrid.kurl.sh/api/v1/runs?searchRef=${STAGING_RELEASE}")

  # check if run exist
  if echo "${testgrid_run_json}" | jq -e '.total == 0' &>/dev/null; then
    bail "Did not find testgrid run for release ${STAGING_RELEASE}"
  fi

  local run_id
  local success_count
  local failure_count
  local total_runs
  local skipped_test_count
  run_id=$(echo "${testgrid_run_json}" | jq -r '.runs[].id')
  success_count=$(echo "${testgrid_run_json}" | jq -r '.runs[].success_count')
  failure_count=$(echo "${testgrid_run_json}" | jq -r '.runs[].failure_count')
  total_runs=$(echo "${testgrid_run_json}" | jq -r '.runs[].total_runs')

  log "Found Testgrid run: https://api.testgrid.kurl.sh/api/v1/run/${run_id}"
  log "Testgrid run details:"
  echo "${testgrid_run_json}" | jq

  # determine the number of test instances that are unsupported for the test run
  skipped_test_count=$(curl -d {} -s "https://api.testgrid.kurl.sh/api/v1/run/${run_id}" | jq '.instances[].isUnsupported' | grep -c true)

  if [[ $((success_count + failure_count + skipped_test_count)) -ne ${total_runs} ]]; then
    bail "Testgrid run ${run_id} seems to have pending runs"
  fi
}

main "$@"
