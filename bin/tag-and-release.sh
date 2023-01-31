#!/bin/bash

set -euo pipefail

function log() {
    echo "$1" 1>&2
}

function bail() {
    log "$1"
    exit 1
}

function parse_flags() {
    for i in "$@"; do
        case ${1} in
            --no-main)
                no_main="1"
                shift
                ;;
            --outdated)
                outdated="1"
                shift
                ;;
            --commit-id=*)
                commit_id="${1#*=}"
                shift
                ;;
            *)
                bail "Unknown flag $1"
                ;;
        esac
    done
}

function require_branch_main() {
    local branch=
    branch="$(git rev-parse --abbrev-ref HEAD)"
    if [ "$branch" != "main" ]; then
        bail "Must be on branch main"
    fi
}

function require_branch_up_to_date() {
    if ! git status -uno | grep -q "Your branch is up to date with" ; then
        bail "Branch must be up to date"
    fi
}

function require_commits() {
    local previous_tag=$1

    local commits=
    commits="$(git rev-list --count "$previous_tag"..HEAD)"

    if [ -z "$commits" ] || [ "$commits" -le 0 ]; then
        bail "Must be at least one commit"
    fi
}

function find_previous_tag() {
    local previous_tag=
    previous_tag="$(git describe --tags "$(git rev-list --tags --max-count=1)")"

    if [ -z "$previous_tag" ]; then
        bail "Failed to find previous tag"
    fi

    echo "$previous_tag"
}

function find_next_tag() {
    local previous_tag=$1

    local today=
    today="$(date -u +%Y.%m.%d)"

    local i=0
    if echo "$previous_tag" | grep -qF "$today" ; then
        i="$(echo "$previous_tag" | awk -F'-' '{print $2}')"
        i=$((i+1))
    fi
    echo "v$today-$i"
}

function main() {
    local no_main=0
    local outdated=0
    local commit_id=
    commit_id=$(git rev-parse --short HEAD)
    parse_flags "$@"

    git fetch -q

    if [ "$no_main" != "1" ]; then
        require_branch_main
    fi
    if [ "$outdated" != "1" ]; then
        require_branch_up_to_date
    fi

    local previous_tag=
    previous_tag="$(find_previous_tag)"

    require_commits "$previous_tag"

    local tag=
    tag="$(find_next_tag "$previous_tag")"

    echo "Tagging and releasing version $tag (${commit_id}) with commits:"
    echo ""

    git log --pretty=oneline "$previous_tag"..."${commit_id}"
    echo ""

    local confirm=
    echo -n "Are you sure? [yes/N] " && read -r confirm && [ "${confirm:-N}" = "yes" ]
    echo ""

    (set -x; git tag -a -m "Release $tag" "$tag" "${commit_id}" && git push origin "$tag")
}

main "$@"
