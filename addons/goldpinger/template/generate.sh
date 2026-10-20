#!/bin/bash

set -euo pipefail

VERSION=""
CHARTVERSION=""

function sed_i() {
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

function add_as_latest() {
    if ! grep -q "\"${VERSION}-${CHARTVERSION}\"" ../../../web/src/installers/versions.js; then
        sed_i "/cron-goldpinger-update/a\\
    \"${VERSION}-${CHARTVERSION}\"," ../../../web/src/installers/versions.js
    fi
}

function get_latest_bloomberg_version() {
    # Get latest versions from Bloomberg chart
    VERSION=$(helm show chart goldpinger/goldpinger | \
        grep -i "^appVersion" | \
        grep -Eo "[0-9]\.[0-9]+\.[0-9]+")
    CHARTVERSION=$(helm show chart goldpinger/goldpinger | \
        grep -i "^version" | \
        grep -Eo "[0-9]+\.[0-9]+\.[0-9]+")
}

# Keep older releases on upstream images; use SecureBuild from release 3.11.3 onward.
function use_securebuild_images() {
    local dir="$1"
    [ "$(printf '%s\n' "3.11.3" "$VERSION" | sort -V | head -n 1)" = "3.11.3" ] || return 0

    # Preserve the component version while translating the repository.
    local replacements=
    replacements="$(cat <<'SED'
/^[[:space:]]*#/b
s~(^|[[:space:]"'=])(docker\.io/)?bloomberg/goldpinger:(v?[0-9][[:alnum:]._-]*)(@sha256:[[:xdigit:]]+)?~\1docker.io/kurlsh/goldpinger:\3~g
SED
)"
    # Use the same file list for verification and rewriting to keep them aligned.
    local files=() file=
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find "$dir" -type f \( -name Manifest -o -name '*.yaml' -o -name '*.sh' \) -print0)
    bash ../../../bin/verify-securebuild-images.sh "$dir/Manifest" "$replacements" "${files[@]}" || return 1
    sed_i -E "$replacements" "${files[@]}"
}

function generate_bloomberg_dynamic() {
    local final_dir="../$VERSION-$CHARTVERSION"
    # Generate and verify into a staging directory and move it into place only
    # after every step succeeds, so a failed run never leaves a half-generated
    # version directory that later runs would skip as already existing.
    local dir="../.${VERSION}-${CHARTVERSION}.tmp"
    rm -rf "$dir"

    # Make the base set of files
    mkdir -p "$dir"
    cp -r ./base/* "$dir"

    # Get a copy of the stack using Bloomberg chart
    helm template goldpinger goldpinger/goldpinger --version "$CHARTVERSION" --values ./values-bloomberg.yaml -n kurl --include-crds > "$dir/goldpinger.yaml"

    # Update version placeholders in install.sh (always use canonical template)
    sed_i "s/__GOLDPINGER_VERSION__/$VERSION-$CHARTVERSION/g" "$dir/install.sh"

    # Generate manifest from the rendered image
    grep 'image: '  "$dir/goldpinger.yaml" | sed 's/ *image: "*\(.*\)\/\(.*\):\([^"]*\)"*/image \2 \1\/\2:\3/' > "$dir/Manifest"

    use_securebuild_images "$dir"

    mv "$dir" "$final_dir"

    echo "Generated Bloomberg goldpinger version: $VERSION-$CHARTVERSION"
}


function parse_flags() {
    for i in "$@"; do
        case ${1} in
            --force)
                force_flag="1"
                shift
                ;;
            --version=*)
                version_flag="${i#*=}"
                shift
                ;;
            *)
                echo "Unknown flag $1"
                exit 1
                ;;
        esac
    done
}

function main() {
    local force_flag=
    local version_flag=
    
    parse_flags "$@"
    
    # Use Bloomberg chart (official chart going forward)
    helm repo add goldpinger https://bloomberg.github.io/goldpinger
    helm repo update
    
    # Get versions
    if [ -n "$version_flag" ]; then
        VERSION="$( echo "$version_flag" | cut -d'-' -f1 )"
        CHARTVERSION="$( echo "$version_flag" | cut -d'-' -f2 )"
    else
        get_latest_bloomberg_version
    fi

    if [ -d "../${VERSION}-${CHARTVERSION}" ]; then
        if [ "$force_flag" == "1" ]; then
            echo "forcibly updating existing version of goldpinger"
            rm -rf "../${VERSION}-${CHARTVERSION}"
        else
            echo "not updating existing version of goldpinger"
            return
        fi
    fi

    generate_bloomberg_dynamic

    # Register the version only after it has been generated and verified, so a
    # failed run cannot leave a stale version registered in versions.js.
    add_as_latest

    if [ -n "${GITHUB_OUTPUT:-}" ]; then
        echo "goldpinger_version=$VERSION-$CHARTVERSION" >> "$GITHUB_OUTPUT"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
