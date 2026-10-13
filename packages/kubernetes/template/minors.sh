#!/bin/bash

# Shared by script.sh and add-minor.sh: how the Kubernetes minors kURL tracks are discovered.
# A minor N (Kubernetes 1.N) is tracked when packages/kubernetes/template/Dockerfile.1<N> exists.
# The factory's detect_kubernetes_minor.py mirrors KURL_MINOR_RE; keep the two in sync.

KURL_MINOR_RE='^[1-9][0-9]?$'

# KURL_MINOR_WINDOW is how many minors have a Dockerfile: add-minor.sh N leaves exactly 1.<N-3>..1.N.
# shellcheck disable=SC2034 # used by add-minor.sh
KURL_MINOR_WINDOW=4

# list_supported_minors prints the tracked minors, newest first, one per line (e.g. "37"), from the
# Dockerfile.1<minor> files in the given directory (default: the current directory).
function list_supported_minors() {
    local dir="${1:-.}"
    local dockerfile=
    local minor=
    for dockerfile in "$dir"/Dockerfile.1*; do
        [ -f "$dockerfile" ] || continue
        minor="${dockerfile##*/Dockerfile.1}"
        [[ "$minor" =~ $KURL_MINOR_RE ]] || continue
        echo "$minor"
    done | sort -rn
}
