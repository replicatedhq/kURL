#!/bin/bash
# this script assumes it is run within <kurl>/addons/contour/template

set -euo pipefail

# get the upstream url that the contour yaml can be found at permanently
UPSTREAM_URL=$(curl -Ls -m 60 -o /dev/null -w %{url_effective} https://projectcontour.io/quickstart/contour.yaml) # https://raw.githubusercontent.com/projectcontour/contour/release-1.11/examples/render/contour.yaml
echo "upstream URL: $UPSTREAM_URL"

# determine the short version (major.minor) from that URL
upstreamShortVersionPattern='/release-([0-9]+\.[0-9]+)/'
[[ "$UPSTREAM_URL" =~ $upstreamShortVersionPattern ]]
SHORT_VERSION="${BASH_REMATCH[1]}" # 1.11
echo "short version: $SHORT_VERSION"

# make a temp directory to do work in
tmpdir=$(mktemp -d -t contour-XXXXXXXXXX)

# get a copy of the contour yaml for the current release
curl -Ls -m 60 -o "$tmpdir"/contour.yaml "$UPSTREAM_URL"

# copy that contour yaml into an env var and determine the full contour and envoy versions (major.minor.patch)
fileContents=$(cat "$tmpdir"/contour.yaml)
upstreamContourVersionPattern='/projectcontour/contour:v([0-9]+\.[0-9]+\.[0-9]+)' # hosted on docker.io and ghcr depending on version
[[ "$fileContents" =~ $upstreamContourVersionPattern ]]
CONTOUR_VERSION="${BASH_REMATCH[1]}" # 1.11.0
CONTOUR_VERSION_DASH="${CONTOUR_VERSION//./-}" # 1-11-0

echo "contour version: $CONTOUR_VERSION"
echo "contour_version=$CONTOUR_VERSION" >> "$GITHUB_OUTPUT"

# Hack: backported images changes starting at 1.13.1 and don't carry forward
# Remove this after the next version is released. 
if [ "$CONTOUR_VERSION" = "1.13.1" ]; then
    rm -rf $tmpdir
    exit 0
fi

upstreamEnvoyVersionPattern='docker.io/envoyproxy/envoy:v([0-9]+\.[0-9]+\.[0-9]+)'
[[ "$fileContents" =~ $upstreamEnvoyVersionPattern ]]
ENVOY_VERSION="${BASH_REMATCH[1]}" # 1.16.2

echo "envoy version: $ENVOY_VERSION"

# create directory inside 'contour' as copy of 'base'
mkdir -p "../$CONTOUR_VERSION"
cp -r ./base/* "../$CONTOUR_VERSION"

cat /dev/null > ../$CONTOUR_VERSION/Manifest
grep 'image: '  "$tmpdir/contour.yaml" | sort -u | sed 's/ *image: "*\(.*\)\/\(.*\):\([^"]*\)"*/image \2 \1\/\2:\3/' >> "../$CONTOUR_VERSION/Manifest"

# template 'install.sh' and 'job-image.yaml' with versions
sed -i "s/__releasever__/$CONTOUR_VERSION/g" "../$CONTOUR_VERSION/install.sh"
sed -i "s/__releasever_dash__/$CONTOUR_VERSION_DASH/g" "../$CONTOUR_VERSION/patches/job-image.yaml"

# insert upstream URL into contour.yaml header
sed -i "s|__upstreamurl__|$UPSTREAM_URL|g" "../$CONTOUR_VERSION/contour.yaml"

# remove docker.io from all image name (supports docker ee)
sed -i "s|docker.io/||g" $tmpdir/contour.yaml

# remove namespace and config from contour.yaml

# first, split file by `---`
csplit --quiet --prefix "$tmpdir"/split "$tmpdir"/contour.yaml "/---/" "{*}"

# remove 'namespace' file, move 'config' file
rm $(grep -Hl 'kind: Namespace' "$tmpdir"/split*)
mv $(grep -Hl 'kind: ConfigMap' "$tmpdir"/split*) "../$CONTOUR_VERSION/tmpl-configmap.yaml"

# rejoin files
cat "$tmpdir"/split* >> "../$CONTOUR_VERSION/contour.yaml"

# edit tmpl-configmap.yaml to include configurable CONTOUR_TLS_MINIMUM_PROTOCOL_VERSION
sed -i 's/# minimum-protocol-version: "1.."/  minimum-protocol-version: "$CONTOUR_TLS_MINIMUM_PROTOCOL_VERSION"/' "../$CONTOUR_VERSION/tmpl-configmap.yaml"

# edit contour.yaml to remove `hostPort: 80` and `hostPort: 443`
sed -i '/hostPort: 80/d' "../$CONTOUR_VERSION/contour.yaml"
sed -i '/hostPort: 443/d' "../$CONTOUR_VERSION/contour.yaml"

# get the current list of versions
versions="$(ls .. | grep -e '[0-9]\+\.[0-9]\+\.[0-9]\+' | sort -r -V)"
allversions="$(echo $versions | sed 's/ /", "/g')"

# update the list of versions shown on kurl.sh
sed -i "/cron-contour-update/c\  contour: [\"${allversions}\"], \/\/ cron-contour-update" ../../../web/src/installers/versions.js
