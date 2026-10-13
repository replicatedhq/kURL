#!/bin/bash

# add-minor.sh <N> scaffolds Kubernetes minor 1.N in kURL so that script.sh can generate its packages:
#
#   1. Rotates the template window: renames the oldest Dockerfile.1<old> to Dockerfile.1<N> (git mv
#      when tracked) and rewrites its pkgs.k8s.io v1.<old> repo to v1.<N>. The window stays the same size.
#   2. Adds a "// cron-kubernetes-update-1<N>" marker to web/src/installers/versions.js right after the
#      last entry of the first marker's block, so the current "latest" minor stays first.
#
# Both steps are idempotent, and re-running repairs a rotation undone by a rebase (see rotate_dockerfile). N must be the next minor (newest Dockerfile minor + 1) unless 1.N is
# already scaffolded. Afterwards run: cd packages/kubernetes/template && ./script.sh 1.N.P
#
# Paths resolve relative to this script, so it can be run from any directory. Tests can override
# them with KURL_TEMPLATE_DIR and KURL_VERSIONS_JS.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${KURL_TEMPLATE_DIR:-$SCRIPT_DIR}"
VERSIONS_JS="${KURL_VERSIONS_JS:-$SCRIPT_DIR/../../../web/src/installers/versions.js}"

# list_supported_minors and KURL_MINOR_RE, shared with script.sh
# shellcheck source=packages/kubernetes/template/minors.sh
. "$SCRIPT_DIR/minors.sh"

function log() {
    echo "add-minor: $*"
}

function die() {
    echo "add-minor: error: $*" >&2
    exit 1
}

function usage() {
    echo "usage: $0 <minor>    e.g. $0 38 to add Kubernetes 1.38" >&2
    exit 2
}

# template_minors prints the minors that have a Dockerfile.1<minor> in the template dir, oldest first
function template_minors() {
    list_supported_minors "$TEMPLATE_DIR" | sort -n
}

# rewrite_package_repo rewrites the pkgs.k8s.io v1.<from> repo in a Dockerfile to v1.<to>
function rewrite_package_repo() {
    local file="$1"
    local from="$2"
    local to="$3"
    local tmp=
    tmp="$(mktemp)"
    sed -e "s/v1\.${from}\([^0-9]\)/v1.${to}\1/g" -e "s/v1\.${from}\$/v1.${to}/" "$file" > "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"

    if grep -Eq "v1\.${from}([^0-9]|\$)" "$file"; then
        die "${file##*/} still references v1.${from} after rewrite"
    fi
    grep -q "v1\.${to}/" "$file" || die "${file##*/} does not reference v1.${to}/ after rewrite"
    log "rewrote v1.${from} -> v1.${to} in ${file##*/}"
}

# rotate_dockerfile leaves exactly KURL_MINOR_WINDOW Dockerfiles, 1.<minor - window + 1>..1.<minor>.
# Re-running it repairs the two shapes a rebase that took main's side of the rotation can leave:
# the rotated-out Dockerfile back next to Dockerfile.1<minor> (rename not detected), or
# Dockerfile.1<minor> holding main's copy of the rotated-out Dockerfile (rename detected).
function rotate_dockerfile() {
    local minor="$1"
    local new_file="$TEMPLATE_DIR/Dockerfile.1${minor}"

    # read loop instead of mapfile so this also runs on macOS's bash 3.2
    local minors=()
    local m=
    while read -r m; do
        minors+=("$m")
    done < <(template_minors)
    [ ${#minors[@]} -gt 0 ] || die "no Dockerfile.1<minor> files found in $TEMPLATE_DIR"
    local oldest="${minors[0]}"
    local newest="${minors[$((${#minors[@]} - 1))]}"
    local stale=$((minor - KURL_MINOR_WINDOW))

    if [ -f "$new_file" ]; then
        [ "$minor" = "$newest" ] || die "Dockerfile.1${minor} exists but 1.${minor} is not the newest template minor (1.${newest})"
        if [ ${#minors[@]} -eq $((KURL_MINOR_WINDOW + 1)) ] && [ "$oldest" -eq "$stale" ]; then
            log "Dockerfile.1${oldest} is back next to Dockerfile.1${minor}, rotating it again"
        else
            [ ${#minors[@]} -eq "$KURL_MINOR_WINDOW" ] \
                || die "expected ${KURL_MINOR_WINDOW} Dockerfiles (1.$((stale + 1))..1.${minor}), found: ${minors[*]}"
            local refs=
            refs="$(grep -Eo 'v1\.[0-9]+/' "$new_file" | sort -u | xargs || true)"
            if [ "$refs" = "v1.${stale}/" ]; then
                log "Dockerfile.1${minor} has the v1.${stale}/ package repo of the rotated-out Dockerfile.1${stale}"
                rewrite_package_repo "$new_file" "$stale" "$minor"
                return 0
            fi
            grep -q "v1\.${minor}/" "$new_file" || die "Dockerfile.1${minor} exists but does not reference the v1.${minor}/ package repo"
            local other=
            other="$(grep -Eo 'v1\.[0-9]+/' "$new_file" | grep -v "^v1\.${minor}/\$" | sort -u | xargs || true)"
            [ -z "$other" ] || die "Dockerfile.1${minor} exists but also references other package repos: ${other}"
            log "Dockerfile.1${minor} already exists, skipping Dockerfile rotation"
            return 0
        fi
    else
        [ "$minor" -eq $((newest + 1)) ] || die "expected minor $((newest + 1)) (newest template minor is 1.${newest}), got 1.${minor}"
        [ ${#minors[@]} -eq "$KURL_MINOR_WINDOW" ] \
            || die "expected ${KURL_MINOR_WINDOW} Dockerfiles before rotation, found: ${minors[*]} (update KURL_MINOR_WINDOW in minors.sh if the window changed)"
    fi

    local old_file="$TEMPLATE_DIR/Dockerfile.1${oldest}"
    grep -q "v1\.${oldest}/" "$old_file" || die "Dockerfile.1${oldest} does not reference the v1.${oldest}/ package repo, refusing to rewrite it"

    if command -v git >/dev/null 2>&1 && git -C "$TEMPLATE_DIR" ls-files --error-unmatch "Dockerfile.1${oldest}" >/dev/null 2>&1; then
        git -C "$TEMPLATE_DIR" mv -f "Dockerfile.1${oldest}" "Dockerfile.1${minor}"
        log "git mv Dockerfile.1${oldest} -> Dockerfile.1${minor}"
    else
        mv -f "$old_file" "$new_file"
        log "mv Dockerfile.1${oldest} -> Dockerfile.1${minor} (not tracked by git)"
    fi

    rewrite_package_repo "$new_file" "$oldest" "$minor"
}

function add_versions_js_marker() {
    local minor="$1"
    local marker="// cron-kubernetes-update-1${minor}"

    [ -f "$VERSIONS_JS" ] || die "versions.js not found at $VERSIONS_JS"

    if grep -Eq "^[[:space:]]*// cron-kubernetes-update-1${minor}[[:space:]]*\$" "$VERSIONS_JS"; then
        log "versions.js already has the ${marker} marker, skipping"
        return 0
    fi

    local tmp=
    tmp="$(mktemp)"
    local rc=0
    awk -v marker="$marker" '
        BEGIN { state = 0; done = 0 }
        {
            if (!done) {
                if (state == 0 && $0 ~ /^[[:space:]]*kubernetes:[[:space:]]*\[/) {
                    state = 1
                } else if (state == 1 && $0 ~ /^[[:space:]]*\/\/ cron-kubernetes-update-[0-9]+[[:space:]]*$/) {
                    state = 2
                    indent = $0
                    sub(/\/\/.*$/, "", indent)
                } else if (state == 1 && $0 ~ /^[[:space:]]*\]/) {
                    exit 3
                } else if (state == 2 && $0 !~ /^[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+",?[[:space:]]*$/) {
                    print indent marker
                    done = 1
                }
            }
            print
        }
        END { if (!done) exit 3 }
    ' "$VERSIONS_JS" > "$tmp" || rc=$?
    if [ "$rc" -ne 0 ]; then
        rm -f "$tmp"
        die "could not find a cron-kubernetes-update-* marker block in the kubernetes array of $VERSIONS_JS"
    fi
    cat "$tmp" > "$VERSIONS_JS"
    rm -f "$tmp"

    [ "$(grep -Ec "^[[:space:]]*// cron-kubernetes-update-1${minor}[[:space:]]*\$" "$VERSIONS_JS")" = "1" ] \
        || die "expected exactly one ${marker} marker in $VERSIONS_JS after insertion"
    log "added ${marker} marker to versions.js"
}

function main() {
    [ $# -eq 1 ] || usage
    local minor="$1"
    [[ "$minor" =~ $KURL_MINOR_RE ]] || die "minor must match ${KURL_MINOR_RE} (e.g. 38 for Kubernetes 1.38), got '${minor}'"
    [ -d "$TEMPLATE_DIR" ] || die "template dir not found: $TEMPLATE_DIR"

    rotate_dockerfile "$minor"
    add_versions_js_marker "$minor"

    log "Kubernetes 1.${minor} scaffolded. Next: cd packages/kubernetes/template && ./script.sh 1.${minor}.<patch>"
}

main "$@"
