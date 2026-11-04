#!/bin/bash

# Tests for strip_sticky_header()/build_sticky_body() in sticky-comment-budget.sh.

# shellcheck source=sticky-comment-budget.sh
. ./bin/sticky-comment-budget.sh

testStripStickyHeaderRemovesTrailingMarker() {
  local body
  body="$(printf 'addon-a message\n<!-- Sticky Pull Request Commentaddon-testgrid -->')"

  local result
  result="$(strip_sticky_header "$body" "addon-testgrid")"

  assertEquals "addon-a message" "${result}"
}

testStripStickyHeaderLeavesBodyUnchangedWhenMarkerMissing() {
  local result
  result="$(strip_sticky_header "addon-a message" "addon-testgrid")"

  assertEquals "addon-a message" "${result}"
}

testStripStickyHeaderHandlesEmptyBody() {
  local result
  result="$(strip_sticky_header "" "addon-testgrid")"

  assertEquals "" "${result}"
}

testBuildStickyBodyConcatenatesWhenUnderBudget() {
  local result
  result="$(build_sticky_body "existing entry" "new entry" 60000)"

  assertEquals "$(printf 'existing entry\nnew entry')" "${result}"
}

testBuildStickyBodyUsesOnlyNewMessageWhenNoExisting() {
  local result
  result="$(build_sticky_body "" "new entry" 60000)"

  assertEquals "new entry" "${result}"
}

testBuildStickyBodyPrunesOldestEntriesWhenOverBudget() {
  local existing
  existing="$(printf 'old-entry-%s\n' $(seq 1 2000))"
  local new="brand-new-entry"

  local result
  result="$(build_sticky_body "$existing" "$new" 100)"

  assertTrue '[ "${#result}" -le 100 ]'
  assertContains "${result}" "…older results trimmed…"
  assertContains "${result}" "$new"

  local has_oldest=0
  echo "${result}" | grep -q "old-entry-1$" && has_oldest=1
  assertEquals 0 "${has_oldest}"
}

testBuildStickyBodyKeepsNewestContentAtTheEnd() {
  local existing
  existing="$(printf 'old-entry-%s\n' $(seq 1 2000))"
  local new="brand-new-entry"

  local result
  result="$(build_sticky_body "$existing" "$new" 100)"

  local last_line
  last_line="$(echo "${result}" | tail -n1)"
  assertEquals "$new" "${last_line}"
}

# shellcheck source=/dev/null
. shunit2
