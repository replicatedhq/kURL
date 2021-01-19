#!/bin/bash
# assumptions
# - will only run the latest version of an addon if there are multiple version changes (latest is simple dictionary sort :/ )
# - will run all addon changes in a single spec if multiple addons were changed.

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

PR_NUMBER=$(echo $GITHUB_REF | cut -d"/" -f3)

INSTALLER_AVAILABLE=
prepare_addon() {
  local name=$1

  INSTALLER_AVAILABLE="true"

  # Get the version that's changed
  local version=$(git diff --dirstat=files,0 "origin/${GITHUB_BASE_REF}" -- "addons/${name}" "origin/${GITHUB_BASE_REF}" -- "addons/${name}" | sed 's/^[ 0-9.]\+% addons\///g' | grep -v template | cut -f2 -d"/" | uniq |  sort -r | head -n 1)

  echo "Found Modified Addon: $name-$version"

  # Concat Spec
  echo "$(snakecase_to_camelcase $name):" >> ./testgrid/tgrun/hack/installer.yaml
  echo "  version: ${version}" >> ./testgrid/tgrun/hack/installer.yaml
  echo "  s3Override: https://${S3_BUCKET}.s3.amazonaws.com/pr/${PR_NUMBER}-${GITHUB_SHA:0:7}-${name}-${version}.tar.gz" >> ./testgrid/tgrun/hack/installer.yaml

  # Push to S3
  echo "Building Package: $name-$version.tag.gz"
  
  make "dist/${name}-${version}.tar.gz"
  aws s3 cp "dist/${name}-${version}.tar.gz" "s3://${S3_BUCKET}/pr/${PR_NUMBER}-${GITHUB_SHA:0:7}-${name}-${version}.tar.gz"

  echo "Package pushed to:  s3://${S3_BUCKET}/pr/${PR_NUMBER}-${GITHUB_SHA:0:7}-${name}-${version}.tar.gz"
}

main() {
  echo "Evaluating PR#${PR_NUMBER}..."

  # Take the base branch and figure out which addons changed. Process Each
  for addon in $(git diff --dirstat=files,0 "origin/${GITHUB_BASE_REF}" -- addons/ "origin/${GITHUB_BASE_REF}" -- addons/ | sed 's/^[ 0-9.]\+% addons\///g' | grep -v template | cut -f -1 -d"/" | uniq ) 
  do
    prepare_addon $addon
  done

  if [ -n "${INSTALLER_AVAILABLE}" ]; then
    echo "Installer spec generated."

    MSG="Testgrid Run Executing @ https://testgrid.kurl.sh/run/pr-$(echo $GITHUB_REF | cut -d/ -f3)-${GITHUB_SHA:0:7}"
    echo "::set-output name=installer_available::true"
    echo "::set-output name=msg::$MSG"
    
  else
    echo "::set-output name=installer_available::false"
    echo "No changed addons detected."
  fi
}

snakecase_to_camelcase() {
  echo $1 | sed -r 's/-([a-z])/\U\1/gi' | sed -r 's/^([A-Z])/\l\1/'
}

export -f prepare_addon
main