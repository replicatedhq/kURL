#!/bin/bash

set -euo pipefail

function get_latest_version() {
    VERSION=$(curl -s https://api.github.com/repos/distribution/distribution/releases/latest | \
        grep '"tag_name":' | \
        sed -E 's/.*"([^"]+)".*/\1/' | \
        sed 's/v//')
}

function get_s3cmd_tag() {
    S3CMD_TAG="$(. ../../../bin/s3cmd-get-latest-tag.sh)"
}

# Keep older releases on upstream images; use SecureBuild from release 3.1.2 onward.
function use_securebuild_images() {
    local dir="../$VERSION"
    [ "$(printf '%s\n' "3.1.2" "$VERSION" | sort -V | head -n 1)" = "3.1.2" ] || return 0

    # Preserve the component version while translating the repository.
    local replacements=
    replacements="$(cat <<'SED'
/^[[:space:]]*#/b
s~(^|[[:space:]"'=])(docker\.io/library/)?registry:(v?[0-9][[:alnum:]._-]*)(@sha256:[[:xdigit:]]+)?~\1docker.io/kurlsh/registry:\3~g
SED
)"
    # Use the same file list for verification and rewriting to keep them aligned.
    local files=() file=
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find "$dir" -type f \( -name Manifest -o -name '*.yaml' -o -name '*.sh' \) -print0)
    bash ../../../bin/verify-securebuild-images.sh "$dir/Manifest" "$replacements" "${files[@]}" || return 1
    sed -i -E "$replacements" "${files[@]}"

    local file=
    for file in deployment-pvc.yaml tmpl-deployment-objectstore.yaml; do
        # The SecureBuild image runs the registry binary at /usr/bin/registry.
        sed -i 's|/bin/registry|/usr/bin/registry|' "$dir/$file"
        # Preserve access to existing root-owned PVCs and the HTTPS listener.
        sed -i '/        imagePullPolicy: IfNotPresent/a\
        securityContext:\
          runAsUser: 0' "$dir/$file"
    done
}

# A rebuilt tag must invalidate the cached addon package as well.
function record_s3cmd_image_build() {
    [ "$S3CMD_TAG" = "20260825-a9ea1c6" ] || return 0
    echo "# SecureBuild s3cmd image build: sha256:adbe3dfc5da8713de6eba48b10472c38b07bf1c3500dd023d17aa63ea5e0d7f5" >> "../$VERSION/Manifest"
}

function generate() {
    # make the base set of files
    mkdir -p "../${VERSION}"
    cp -r ./base/* "../${VERSION}"

    # update version in files
    sed -i "s/__registry_version__/$VERSION/g" "../$VERSION/Manifest"
    sed -i "s/__registry_version__/$VERSION/g" "../$VERSION/install.sh"
    sed -i "s/__registry_version__/$VERSION/g" "../$VERSION/deployment-pvc.yaml"
    sed -i "s/__registry_version__/$VERSION/g" "../$VERSION/tmpl-deployment-objectstore.yaml"
    sed -i "s/__S3CMD_TAG__/$S3CMD_TAG/g" "../$VERSION/Manifest"
    sed -i "s/__S3CMD_TAG__/$S3CMD_TAG/g" "../$VERSION/patch-deployment-migrate-s3.yaml"
    sed -i "s/__S3CMD_TAG__/$S3CMD_TAG/g" "../$VERSION/patch-deployment-velero.yaml"
    use_securebuild_images
    record_s3cmd_image_build
}

function add_as_latest() {
    if ! sed '0,/cron-registry-update/d' ../../../web/src/installers/versions.js | sed '/\],/,$d' | grep -q "${VERSION}" ; then
        sed -i "/cron-registry-update/a\    \"${VERSION}\"\," ../../../web/src/installers/versions.js
    fi
}

VERSION=""
S3CMD_TAG=""
function main() {
    get_latest_version
    get_s3cmd_tag

    echo "Found Registry version ${VERSION}"
    echo "Found kurlsh/s3cmd tag ${S3CMD_TAG}"

    local IS_NEW_VERSION=1
    if [ -d "../${VERSION}" ]; then
        rm -rf "../${VERSION}"
        IS_NEW_VERSION=0
    fi

    generate

    if [ "$IS_NEW_VERSION" == "1" ] ; then
        add_as_latest
    fi

    echo "registry_version=$VERSION" >> "$GITHUB_OUTPUT"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
