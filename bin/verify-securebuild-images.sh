#!/bin/bash

set -euo pipefail

# Verify the rewritten Manifest before a generator changes any image references.
manifest="$1"
replacements="$2"
images="$(sed -E "$replacements" "$manifest" | awk '$1 == "image" && $3 ~ /^docker[.]io\/kurlsh\// {print $3}' | sort -u)"

if [ -z "$images" ]; then
    echo "No SecureBuild images found after rewriting $manifest. Check the generator's image rules before generating the add-on." >&2
    exit 1
fi

while IFS= read -r image; do
    if ! docker manifest inspect "$image" >/dev/null; then
        echo "Cannot verify SecureBuild image $image for $manifest. Publish this tag before generating the add-on." >&2
        exit 1
    fi
done <<< "$images"
