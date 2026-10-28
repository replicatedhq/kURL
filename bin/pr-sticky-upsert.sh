#!/bin/bash
#
# pr-sticky-upsert.sh <pr-number> <marker> <title> [key] [line]
#
# Maintains ONE sticky comment on a PR, identified by an HTML-marker substring
# in the body. Two modes:
#
#   ensure: 4 args. Creates the comment (marker + title) if it doesn't exist,
#           then exits. Meant for a single up-front job so parallel jobs later
#           only ever append and never race to create it.
#
#   upsert: 5 args. Appends <line> to the body, or replaces the existing line
#           that starts with <key> (so re-runs of the same logical row don't
#           pile up, while rows from earlier keys are never overwritten).
#
# Read-modify-write against the API is retried with jitter: concurrent
# updaters (matrix legs finishing at the same time) can still clobber each
# other, so after every write the comment is re-read and the line verified,
# retrying until it sticks. If two updaters both create the comment in the
# same instant a duplicate can survive; callers that fan out should pre-create
# via ensure mode (see above).
#
# Required env: GH_TOKEN, GITHUB_REPOSITORY (owner/repo).

set -euo pipefail

PR="${1:?usage: pr-sticky-upsert.sh <pr> <marker> <title> [key] [line]}"
MARKER="${2:?}"
TITLE="${3:?}"
KEY="${4:-}"
LINE="${5:-}"

ENSURE_ONLY=0
if [ -z "$LINE" ]; then
    ENSURE_ONLY=1
fi

find_sticky() {
    gh api "repos/${GITHUB_REPOSITORY}/issues/${PR}/comments?per_page=100" --paginate 2>/dev/null \
        | jq -r --arg m "$MARKER" '.[] | select(.body | contains($m)) | .id' \
        | head -1
}

get_body() {
    # GitHub round-trips bodies with CRLF line endings; normalize so key
    # matching and verification behave.
    gh api "repos/${GITHUB_REPOSITORY}/issues/comments/$1" --jq .body 2>/dev/null | tr -d '\r'
}

create_sticky() {
    local body="${MARKER}"$'\n\n'"${TITLE}"$'\n'
    if [ "$ENSURE_ONLY" = "0" ]; then
        body+=$'\n'"${LINE}"$'\n'
    fi
    jq -n --arg b "$body" '{body: $b}' \
        | gh api -X POST "repos/${GITHUB_REPOSITORY}/issues/${PR}/comments" --input - > /dev/null
}

patch_sticky() {
    jq -n --arg b "$2" '{body: $b}' \
        | gh api -X PATCH "repos/${GITHUB_REPOSITORY}/issues/comments/$1" --input - > /dev/null
}

upsert_line() {
    # stdin: current body. Prints the new body: the line starting with $KEY is
    # replaced by $LINE, otherwise $LINE is appended.
    local body
    body="$(cat)"
    if printf '%s\n' "$body" | grep -qF -- "$KEY"; then
        KEY="$KEY" LINE="$LINE" awk 'BEGIN { key = ENVIRON["KEY"]; line = ENVIRON["LINE"] }
            { if (index($0, key) == 1) print line; else print }' <<< "$body"
    else
        printf '%s\n%s\n' "$body" "$LINE"
    fi
}

for attempt in 1 2 3 4 5 6 7 8; do
    COMMENT_ID="$(find_sticky || true)"

    if [ -z "$COMMENT_ID" ]; then
        create_sticky || true
    elif [ "$ENSURE_ONLY" = "0" ]; then
        OLD="$(get_body "$COMMENT_ID" || true)"
        NEW="$(printf '%s' "$OLD" | upsert_line)"
        patch_sticky "$COMMENT_ID" "$NEW" || true
    fi

    # Verify the write actually landed before declaring victory; a concurrent
    # writer may have overwritten it (last-writer-wins on the API).
    sleep 2
    VERIFY_ID="$(find_sticky || true)"
    if [ -n "$VERIFY_ID" ]; then
        if [ "$ENSURE_ONLY" = "1" ]; then
            echo "sticky comment present (id $VERIFY_ID, attempt $attempt)"
            exit 0
        fi
        CURRENT="$(get_body "$VERIFY_ID" || true)"
        if printf '%s\n' "$CURRENT" | grep -qF -- "$LINE"; then
            echo "sticky comment updated (attempt $attempt)"
            exit 0
        fi
    fi
    sleep $((RANDOM % 5 + 2))
done

echo "::warning ::could not update the PR sticky comment after 8 attempts"
if [ "$ENSURE_ONLY" = "0" ]; then
    printf 'dropped line: %s\n' "$LINE"
fi
exit 1
