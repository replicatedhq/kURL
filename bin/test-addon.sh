#!/bin/bash

set -eo pipefail

function require() {
   if [ -z "$2" ]; then
       echo "validation failed: $1 unset"
       exit 1
   fi
}

function run_testgrid_test() {
  local addon="$1"
  local version="$2"
  local s3_url="$3"
  local test_spec="$4"
  local testgrid_os_spec_path="$5"
  local prefix="$6"
  local priority="$7"
  local staging="$8"

  local tmpdir=
  tmpdir="$(mktemp -d)"
  cp "$test_spec" "$tmpdir/test-spec"
  cp "$testgrid_os_spec_path" "$tmpdir/os-spec"

  echo "Found test spec template $test_spec"

  # Substitute
  sed -i "s#__testver__#${version}#g" "$tmpdir/test-spec"
  sed -i "s#__testdist__#${s3_url}#g" "$tmpdir/test-spec"

  # include the following in the ref for uniqueness:
  # - the filename of the test spec
  # - datetime
  local ref=
  ref="$prefix-$addon-$version-$(basename "$test_spec" ".yaml")-$(date --utc +%FT%TZ)"

  local staging_flag=
  if [ "$staging" = "1" ]; then
    staging_flag="--staging"
  fi

  # Run testgrid plan
  ( set -x ; docker run --rm -e TESTGRID_API_TOKEN -v "$tmpdir:/wrk" -w /wrk \
    replicated/tgrun:latest queue \
      "$staging_flag" \
      --ref "$ref" \
      --spec /wrk/test-spec \
      --os-spec /wrk/os-spec \
      --priority "$priority" )
  echo "Submitted TestGrid Ref $ref"
  MSG="$MSG https://testgrid.kurl.sh/run/$ref"
}

function main() {
  local addon="$1"
  local version="$2"
  local s3_url="$3"
  local testgrid_spec_path="$4"
  local testgrid_os_spec_path="$5"
  local prefix="$6"
  local priority="${7:-0}"
  local staging="$8"

  # if this is triggered by automation, lower the priority
  if [ "$priority" = "0" ] && [ "$GITHUB_ACTOR" = "replicated-ci-kurl" ]; then
    priority=-1
  fi

  # From GH Action Defition
  require TESTGRID_API_TOKEN "$TESTGRID_API_TOKEN"

  echo "Test Addon $addon-$version"

  local MSG="Testgrid Run(s) Executing @ "

  # Run for each template (if available)
  shopt -s nullglob
  for test_spec in "$testgrid_spec_path"/*.yaml; do
    run_testgrid_test "$addon" "$version" "$s3_url" "$test_spec" "$testgrid_os_spec_path" "$prefix" "$priority" "$staging"
  done
  for test_spec in "$testgrid_spec_path"/*.yml; do
    run_testgrid_test "$addon" "$version" "$s3_url" "$test_spec" "$testgrid_os_spec_path" "$prefix" "$priority" "$staging"
  done
  shopt -u nullglob

  echo "message=$MSG" >> "$GITHUB_OUTPUT"
  echo "::notice ::${MSG}"
  echo "Run completed."
}

main "$@"
