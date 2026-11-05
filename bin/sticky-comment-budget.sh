#!/bin/bash
# Keeps the addon-testgrid sticky PR comment under GitHub's 65,536-char comment
# body limit by pruning the oldest entries once existing + new content would
# exceed a safe budget, instead of letting append:true grow it unbounded.

# Strips the trailing marocchino/sticky-pull-request-comment hidden header
# line from a comment body fetched via the API, so it isn't duplicated or
# combined mid-document when we rebuild the body ourselves.
function strip_sticky_header() {
  local body="${1:-}"
  local header="${2:?strip_sticky_header: header required}"
  local marker=$'\n'"<!-- Sticky Pull Request Comment${header} -->"

  if [ "${body: -${#marker}}" = "$marker" ]; then
    body="${body:0:${#body}-${#marker}}"
  fi
  printf '%s' "$body"
}

# Combines the existing sticky body with the new message, pruning the oldest
# entries (from the front) when the result would exceed max_len.
function build_sticky_body() {
  local existing="${1:-}"
  local new_message="${2:?build_sticky_body: new message required}"
  local max_len="${3:-60000}"

  local combined
  if [ -z "$existing" ]; then
    combined="$new_message"
  else
    combined="${existing}
${new_message}"
  fi

  if [ "${#combined}" -le "$max_len" ]; then
    printf '%s' "$combined"
    return 0
  fi

  local note='…older results trimmed…'
  local budget=$(( max_len - ${#note} - 1 ))
  if [ "$budget" -lt 0 ]; then
    budget=0
  fi
  local tail="${combined: -${budget}}"
  printf '%s\n%s' "$note" "$tail"
}
