#!/bin/bash
# assumptions
# - will only run the latest version of an addon if there are multiple version changes (latest is simple dictionary sort :/ )
# - will run each changed addon as a separate testgrid run. Testing two addon updates simultaneously in a TestGrid run is not supported.

set -eo pipefail

function require() {
   if [ -z "$2" ]; then
       echo "validation failed: $1 unset"
       exit 1
   fi
}

# Defaults from GH Action
require GITHUB_BASE_REF "${GITHUB_BASE_REF}"
require GITHUB_REF "${GITHUB_REF}"
require GITHUB_SHA "${GITHUB_SHA}"

# From GH Action Defition
require AWS_ACCESS_KEY_ID "${AWS_ACCESS_KEY_ID}"
require AWS_SECRET_ACCESS_KEY "${AWS_SECRET_ACCESS_KEY}"
require S3_BUCKET "${S3_BUCKET}"

# These addons aren't part of the spec. (containerd doesn't use addon.sh)
ADDON_DENY_LIST="aws calico nodeless containerd"

PR_NUMBER=$(echo $GITHUB_REF | cut -d"/" -f3)

# Checks if there is an update to a addon that meets all of the right criteria and reports to the action
# - Not an update to the template
# - Not an update to a readme
# - Not a addon in the ADDON_DENY_LIST (not part of the spec)
ADDON_AVAILBLE=
check() {
  echo "Checking PR#${PR_NUMBER}..."

  # Take the base branch and figure out which addons changed. Verify each.
  for addon in $(git diff --dirstat=files,0 "origin/${GITHUB_BASE_REF}" -- addons/ "origin/${GITHUB_BASE_REF}" -- addons/ | sed 's/^[ 0-9.]\+% addons\///g' | grep -v template | cut -f -1 -d"/" | uniq ) 
  do
    if ! [[ " $ADDON_DENY_LIST " =~ .*\ $addon\ .* ]]; then
      check_addon $addon
    fi
  done

  if [ -n "${ADDON_AVAILBLE}" ]; then
    echo "Modified addons detected. Continuing with action..."
    echo "::set-output name=addons_available::true"    
  else
    echo "No changed addons detected, addon is currently in the ADDON_DENY_LIST, or addon does not have a TestGrid template."
    echo "::set-output name=addons_available::false"
  fi
}

modified_versions() {
  local name=$1

  # Get the version that's changed (filter out templates)
  local versions=$(git diff --dirstat=files,0 "origin/${GITHUB_BASE_REF}" -- "addons/${name}" "origin/${GITHUB_BASE_REF}" -- "addons/${name}" | sed 's/^[ 0-9.]\+% addons\///g' | grep -v template | cut -f2 -d"/" | uniq |  sort -r )

  echo $versions
}

check_addon() {
  local name=$1

  # Get the version that's changed (filter out templates)
  local versions=$(modified_versions $name)

  # check if there is a valid version (files in the root don't count) & template files 
  for version in $versions
  do
    shopt -s nullglob
    if [ -n "${version}" ] && compgen -G "./addons/$name/template/testgrid/*.yaml" > /dev/null; then
      ADDON_AVAILBLE=true

      echo "Found Modified Addon: $name-$version"
    fi
    shopt -u nullglob
  done
}

run_addon() {
  local name=$1

  # Get the version that's changed
  local versions=$(modified_versions $name)

  for version in $versions
  do
    # check if there is a valid version (files in the root don't count)
    if [ -n "${version}" ]; then
      echo "Testing Modified Addon: $name-$version"

      # Build Packages
      echo "Building Package: $name-$version.tag.gz"

      make "dist/${name}-${version}.tar.gz"
      aws s3 cp "dist/${name}-${version}.tar.gz" "s3://${S3_BUCKET}/pr/${PR_NUMBER}-${GITHUB_SHA:0:7}-${name}-${version}.tar.gz"

      echo "Package pushed to:  s3://${S3_BUCKET}/pr/${PR_NUMBER}-${GITHUB_SHA:0:7}-${name}-${version}.tar.gz"

      # Run for each template (if available)
      shopt -s nullglob
      for test_spec in ./addons/$name/template/testgrid/*.yaml;
      do
        test_addon $name $version $test_spec
      done
      shopt -u nullglob
    fi
  done
}

test_addon() {
  local name=$1
  local version=$2
  local test_spec=$3

  echo "Found test spec template $test_spec."

  # Substitute
  local dist="https://${S3_BUCKET}.s3.amazonaws.com/pr/${PR_NUMBER}-${GITHUB_SHA:0:7}-${name}-${version}.tar.gz"
  sed -i "s#__testver__#${version}#g" $test_spec
  sed -i "s#__testdist__#${dist}#g" $test_spec

  # Run testgrid plan
  ./testgrid/tgrun/bin/tgrun queue --staging --ref "pr-${PR_NUMBER}-${GITHUB_SHA:0:7}-${name}-${version}" --spec "$(cat $test_spec)"
  echo "Submitted TestGrid Ref pr-${PR_NUMBER}-${GITHUB_SHA:0:7}-${name}-${version}"
  MSG="$MSG https://testgrid.kurl.sh/run/pr-${PR_NUMBER}-${GITHUB_SHA:0:7}-${name}-${version}"
}

MSG="Testgrid Run(s) Executing @ "
run() {
  echo "Test PR#${PR_NUMBER}..."

  # Take the base branch and figure out which addons changed. Verify each.
  for addon in $(git diff --dirstat=files,0 "origin/${GITHUB_BASE_REF}" -- addons/ "origin/${GITHUB_BASE_REF}" -- addons/ | sed 's/^[ 0-9.]\+% addons\///g' | grep -v template | cut -f -1 -d"/" | uniq ) 
  do
    if ! [[ " $ADDON_DENY_LIST " =~ .*\ $addon\ .* ]]; then
      run_addon $addon
    fi
  done

  
  echo "::set-output name=msg::${MSG}"   
  echo "Run completed."
}
