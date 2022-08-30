#!/bin/bash
# assumptions
# - will run each changed addon as a separate testgrid run. Testing two addon updates simultaneously in a TestGrid run is not supported.

set -eo pipefail

# These addons aren't part of the spec. (containerd doesn't use addon.sh)
ADDON_DENY_LIST="aws calico nodeless"

function require() {
   if [ -z "$2" ]; then
       echo "validation failed: $1 unset"
       exit 1
   fi
}

# Checks if there is an update to a addon that meets all of the right criteria and reports to the action
# - Not an update to the template or build-images
# - Not an update to a readme
# - Not a addon in the ADDON_DENY_LIST (not part of the spec)
ADDONS_AVAILBLE=()
function check() {
  # Defaults from GH Action
  require GITHUB_BASE_REF "${GITHUB_BASE_REF}"
  require GITHUB_REF "${GITHUB_REF}"
  require GITHUB_SHA "${GITHUB_SHA}"

  PR_NUMBER="$(echo "$GITHUB_REF" | cut -d"/" -f3)"

  echo "Checking PR#${PR_NUMBER}..."

  # Take the base branch and figure out which addons changed. Verify each.
  for addon in $(git diff --dirstat=files,0 "origin/${GITHUB_BASE_REF}" -- addons/ "origin/${GITHUB_BASE_REF}" -- addons/ | sed 's/^[ 0-9.]\+% addons\///g' | grep -v template | grep -v build-images | cut -f -1 -d"/" | uniq )
  do
    if ! [[ " $ADDON_DENY_LIST " =~ .*\ $addon\ .* ]]; then
      check_addon "$addon"
    fi
  done

  if [ "${#ADDONS_AVAILBLE[@]}" -gt "0" ]; then
    echo "Modified addons detected. Continuing with action..."
    echo "::set-output name=addons::{\"include\":[$(join_array_by ',' "${ADDONS_AVAILBLE[@]}")]}"
  else
    echo "No changed addons detected, addon is currently in the ADDON_DENY_LIST, or addon does not have a TestGrid template."
  fi
}

function join_array_by {
  local d=${1-} f=${2-}
  if shift 2; then
    printf %s "$f" "${@/#/$d}"
  fi
}

function modified_versions() {
  local addon=$1

  # Get the version that's changed (filter out templates and build-images)
  local versions=
  versions=$(git diff --dirstat=files,0 "origin/${GITHUB_BASE_REF}" -- "addons/${addon}" "origin/${GITHUB_BASE_REF}" -- "addons/${addon}" | sed 's/^[ 0-9.]\+% addons\///g' | grep -v template | grep -v build-images | cut -f2 -d"/" | uniq |  sort -r )

  echo "$versions"
}

function check_addon() {
  local addon=$1

  # Get the version that's changed (filter out templates and build-images)
  local versions=
  versions=$(modified_versions "$addon")

  local prefix=
  prefix="pr-$(echo "$GITHUB_REF" | cut -d"/" -f3)-${GITHUB_SHA:0:7}"

  # check if there is a valid version (files in the root don't count) & template files
  for version in $versions
  do
    shopt -s nullglob
    if compgen -G "./addons/$addon/template/testgrid/*.yaml" > /dev/null; then
      ADDONS_AVAILBLE+=('{"addon":"'"$addon"'","version":"'"$version"'","prefix":"'"$prefix"'"}')

      echo "Found Modified Addon: $addon-$version"
    fi
    shopt -u nullglob
  done
}

function run_addon() {
  local addon="$1"
  local version="$2"
  local prefix="$3"

  echo "Testing Modified Addon: $addon-$version"

  # Build Packages
  echo "Building Package: $addon-$version.tag.gz"

  local key="pr/${prefix}-${addon}-${version}.tar.gz"

  make "dist/${addon}-${version}.tar.gz"
  aws s3 cp "dist/${addon}-${version}.tar.gz" "s3://${S3_BUCKET}/$key" --region us-east-1

  echo "Package pushed to: s3://${S3_BUCKET}/$key"

  # make clean to free up space
  make clean

  # Run for each template (if available)
  shopt -s nullglob
  for test_spec in ./addons/"$addon"/template/testgrid/*.yaml; do
    test_addon "$addon" "$version" "$test_spec" "$key"
  done
  shopt -u nullglob
}

function test_addon() {
  local addon="$1"
  local version="$2"
  local test_spec="$3"
  local key="$4"

  cp "$test_spec" /tmp/test-spec

  echo "Found test spec template $test_spec."

  # Substitute
  local s3_url="https://${S3_BUCKET}.s3.amazonaws.com/${key}"
  sed -i "s#__testver__#${version}#g" /tmp/test-spec
  sed -i "s#__testdist__#${s3_url}#g" /tmp/test-spec

  # if this is triggered by automation, lower the priority
  local priority=0
  if [ "$GITHUB_ACTOR" = "replicated-ci-kurl" ]; then
    priority=-1
  fi

  # include the following in the ref for uniqueness:
  # - the filename of the test spec
  # - datetime
  local ref=
  ref="${prefix}-${addon}-${version}-$(basename "$test_spec" ".yaml")-$(date --utc +%FT%TZ)"

  # Run testgrid plan
  docker run --rm -e TESTGRID_API_TOKEN -v `pwd`:/wrk -w /wrk \
    replicated/tgrun:latest queue --staging \
      --ref "$ref" \
      --spec /tmp/test-spec \
      --os-spec ./testgrid/specs/os-firstlast.yaml \
      --priority "$priority"
  echo "Submitted TestGrid Ref $ref"
  MSG="$MSG https://testgrid.kurl.sh/run/$ref"
}

MSG="Testgrid Run(s) Executing @ "
function run() {
  local addon="$1"
  local version="$2"
  local prefix="$3"

  # From GH Action Defition
  require AWS_ACCESS_KEY_ID "${AWS_ACCESS_KEY_ID}"
  require AWS_SECRET_ACCESS_KEY "${AWS_SECRET_ACCESS_KEY}"
  require S3_BUCKET "${S3_BUCKET}"

  echo "Test Addon ${addon}-${version}"

  run_addon "$addon" "$version" "$prefix"

  echo "::set-output name=msg::${MSG}"
  echo "Run completed."
}
