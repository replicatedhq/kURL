#!/bin/bash
set -eo pipefail

function bail() {
    log "$1"
    exit 1
}

function commandExists() {
    command -v "$@" > /dev/null 2>&1
}

function log() {
    echo "$1" 1>&2
}

function require() {
    if [ -z "$2" ]; then
        echo "validation failed: $1 unset"
        exit 1
    fi
}

function retry {
    local retries=$1
    shift

    local count=0
    until "$@"; do
        exit=$?
        wait=$((2 ** count))
        count=$((count + 1))
        if [ "$count" -lt "$retries" ]; then
            echo "Retry $count/$retries exited $exit, retrying in $wait seconds..."
            sleep $wait
        else
            echo "Retry $count/$retries exited $exit, no more retries left."
            return $exit
        fi
    done
    return 0
}
# export the retry function so that the parallel command can use it
export -f retry

require AWS_ACCESS_KEY_ID "${AWS_ACCESS_KEY_ID}"
require AWS_SECRET_ACCESS_KEY "${AWS_SECRET_ACCESS_KEY}"
require AWS_REGION "${AWS_REGION}"
require S3_BUCKET "${S3_BUCKET}"
require STAGING_RELEASE "${STAGING_RELEASE}"
require VERSION_TAG "${VERSION_TAG}"

PACKAGE_PREFIX="${PACKAGE_PREFIX:-dist}"
STAGING_PREFIX="${STAGING_PREFIX:-staging}"
JOBS_FILE="${JOBS_FILE:-/tmp/s3_cp_jobs.txt}"
PARALLEL_JOBS="${PARALLEL_JOBS:-10}"

function main() {

  # GNU parallel is required for this script to perform parallel s3 cp operations
  if ! commandExists "parallel"; then
    bail "GNU parallel is not installed."
  fi

  # need jq
  if ! commandExists "jq"; then
    bail "jq is not installed."
  fi

  # exclude common and kurl-bin-utils packages since they will be rebuilt during the prod release
  # jq -rc '.[]' => get the raw string values
  # tail -n +2 => skip empty key in first line of output
  local packages=
  packages=$(aws s3api list-objects-v2 --bucket "${S3_BUCKET}" --prefix "${STAGING_PREFIX}/${STAGING_RELEASE}" --query 'Contents[].Key' | jq -rc '.[]' | tail -n +2 | grep -vE "/common.*" | grep -vE "/kurl-bin-utils-*")

  log "Objects that will be copied to s3://${S3_BUCKET}/${PACKAGE_PREFIX}/${VERSION_TAG}:"
  log "${packages}"

  # create jobs file for parallel uploads
  local package_name=
  while IFS= read -r package; do
    # remove prefix
    package_name=$(echo "${package}" | awk '{print $NF}' FS=/)

    # each copy-object command will be its own parallel job
    echo retry 5 aws s3api copy-object --copy-source "${S3_BUCKET}/${STAGING_PREFIX}/${STAGING_RELEASE}/${package_name}" --bucket "${S3_BUCKET}" --key "${PACKAGE_PREFIX}/${VERSION_TAG}/${package_name}"
  done <<< "${packages}" > "${JOBS_FILE}"

  log "The following aws s3api commands will be executed in parallel:"
  cat "${JOBS_FILE}"

  # run s3 uploads in parallel
  # --wil-cite => don't display citation nag
  # --hatl now,fail=1 => running jobs will be killed immediately if any other job fails
  # --jobs 0 => will run as many jobs in parallel as possible (depends on number of cores)
  # --eta => show progress
  parallel --will-cite --eta --halt now,fail=1 --jobs "${PARALLEL_JOBS}" < "${JOBS_FILE}"

  # cleanup jobs files
  rm "${JOBS_FILE}"
}

main "$@"
