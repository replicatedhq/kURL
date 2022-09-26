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
  local prefix="$5"
  local priority="$6"

  cp "$test_spec" /tmp/test-spec

  echo "Found test spec template $test_spec"

  # Substitute
  sed -i "s#__testver__#${version}#g" /tmp/test-spec
  sed -i "s#__testdist__#${s3_url}#g" /tmp/test-spec

  # include the following in the ref for uniqueness:
  # - the filename of the test spec
  # - datetime
  local ref=
  ref="$prefix-$addon-$version-$(basename "$test_spec" ".yaml")-$(date --utc +%FT%TZ)"

  # Run testgrid plan
  docker run --rm -e TESTGRID_API_TOKEN -v "$(pwd)":/wrk -v /tmp/test-spec:/tmp/test-spec -w /wrk \
    replicated/tgrun:latest queue --staging \
      --ref "$ref" \
      --spec /tmp/test-spec \
      --os-spec ./testgrid/specs/os-firstlast.yaml \
      --priority "$priority"
  echo "Submitted TestGrid Ref $ref"
  MSG="$MSG https://testgrid.kurl.sh/run/$ref"
}

function main() {
  local addon="$1"
  local version="$2"
  local s3_url="$3"
  local testgrid_spec_path="$4"
  local prefix="$5"
  local priority="${6:-0}"

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
    run_testgrid_test "$addon" "$version" "$s3_url" "$test_spec" "$prefix" "$priority"
  done
  for test_spec in "$testgrid_spec_path"/*.yml; do
    run_testgrid_test "$addon" "$version" "$s3_url" "$test_spec" "$prefix" "$priority"
  done
  shopt -u nullglob

  echo "::set-output name=message::${MSG}"
  echo "::notice ::${MSG}"
  echo "Run completed."
}

main "$@"
