#!/bin/bash

set -euo pipefail

# Verify the Manifest and every file the generator will rewrite, before changing output.
manifest="$1"
replacements="$2"
shift 2
images="$(sed -E "$replacements" "$manifest" | awk '$1 == "image" && $3 ~ /^docker[.]io\/kurlsh\// {print $3}' | sort -u)"

if [ -z "$images" ]; then
    echo "No SecureBuild images found after rewriting $manifest. Check the generator's image rules before generating the add-on." >&2
    exit 1
fi

for file in "$manifest" "$@"; do
    file_images="$(sed -E "$replacements" "$file" | awk '
        /^[[:space:]]*#/ {next}
        {
            rest = $0
            sub(/[[:space:]]+#.*/, "", rest)
            while (match(rest, /docker[.]io\/kurlsh\/[[:alnum:].\/_:@-]+/)) {
                print substr(rest, RSTART, RLENGTH)
                rest = substr(rest, RSTART + RLENGTH)
            }
        }
    ' | sort -u)"
    while IFS= read -r image; do
        [ -n "$image" ] || continue
        if ! grep -Fxq -- "$image" <<< "$images"; then
            echo "SecureBuild image $image in $file is not bundled in $manifest. Add it to the Manifest before generating the add-on." >&2
            exit 1
        fi
    done <<< "$file_images"
done

while IFS= read -r image; do
    if ! docker manifest inspect "$image" >/dev/null; then
        echo "Cannot verify SecureBuild image $image for $manifest. Publish this tag before generating the add-on." >&2
        exit 1
    fi
done <<< "$images"
