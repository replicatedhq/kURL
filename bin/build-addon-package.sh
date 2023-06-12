#!/bin/bash

set -eo pipefail

function require() {
   if [ -z "$2" ]; then
       echo "validation failed: $1 unset"
       exit 1
   fi
}

function build_addon() {
  local addon="$1"
  local version="$2"
  local addon_path="$3"
  local prefix="$4"

  local s3_key="pr/${prefix}-$addon-$version.tar.gz"

  # make "dist/$addon-$version.tar.gz"
  local tmpdir=
  tmpdir="$(mktemp -d)"
  local addon_dir="addons/$addon/$version"
  ./bin/save-manifest-assets.sh "$addon-$version" "$addon_path/Manifest" "$tmpdir/$addon_dir"
  mkdir -p "$tmpdir/$addon_dir"
  cp -r "$addon_path/." "$tmpdir/$addon_dir/"
  tar cf - -C "$tmpdir" "$addon_dir" | gzip > "$tmpdir/$addon-$version.tar.gz"

  aws s3 cp "$tmpdir/$addon-$version.tar.gz" "s3://${S3_BUCKET}/$s3_key" --region us-east-1

  echo "Package pushed to: s3://${S3_BUCKET}/$s3_key"
  echo "addon_package_url=https://$S3_BUCKET.s3.amazonaws.com/$s3_key" >> "$GITHUB_OUTPUT"
}

function main() {
  local addon="$1"
  local version="$2"
  local addon_path="$3"
  local prefix="$4"

  # From GH Action Defition
  require AWS_ACCESS_KEY_ID "${AWS_ACCESS_KEY_ID}"
  require AWS_SECRET_ACCESS_KEY "${AWS_SECRET_ACCESS_KEY}"
  require S3_BUCKET "${S3_BUCKET}"

  echo "Build Addon $addon-$version"

  build_addon "$addon" "$version" "$addon_path" "$prefix"

  echo "Build complete."
}

main "$@"
