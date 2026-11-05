#!/bin/bash

# Tests for combine_testgrid_messages()/main() in combine-testgrid-messages.sh.

# shellcheck source=combine-testgrid-messages.sh
. ./bin/combine-testgrid-messages.sh

oneTimeSetUp() {
  WORK_DIR="$(mktemp -d)"
}

oneTimeTearDown() {
  rm -rf "${WORK_DIR}"
}

testCombineMultipleArtifactDirsProducesMultiLineMessage() {
  local dir="${WORK_DIR}/multi"
  mkdir -p "${dir}/addon-a" "${dir}/addon-b"
  printf 'addon-a message\n' > "${dir}/addon-a/addon-testgrid-message.txt"
  printf 'addon-b message\n' > "${dir}/addon-b/addon-testgrid-message.txt"

  local result
  result="$(combine_testgrid_messages "${dir}")"

  assertEquals "$(printf 'addon-a message\naddon-b message')" "${result}"
}

testCombineZeroArtifactDirsProducesEmptyMessage() {
  local dir="${WORK_DIR}/empty"
  mkdir -p "${dir}"

  local result
  result="$(combine_testgrid_messages "${dir}")"

  assertEquals "" "${result}"
}

testCombineMissingTrailingNewlineDoesNotMergeRefsOntoOneLine() {
  local dir="${WORK_DIR}/no-trailing-newline"
  mkdir -p "${dir}/addon-a" "${dir}/addon-b"
  printf 'addon-a message' > "${dir}/addon-a/addon-testgrid-message.txt"
  printf 'addon-b message\n' > "${dir}/addon-b/addon-testgrid-message.txt"

  local result
  result="$(combine_testgrid_messages "${dir}")"

  assertEquals "$(printf 'addon-a message\naddon-b message')" "${result}"
}

testMainWritesEmptyMessageOutputWhenSkippedWithNoArtifacts() {
  local dir="${WORK_DIR}/main-empty"
  mkdir -p "${dir}"
  GITHUB_OUTPUT="$(mktemp)"

  main "${dir}" "skipped"

  assertEquals "message=" "$(cat "${GITHUB_OUTPUT}")"
  rm -f "${GITHUB_OUTPUT}"
}

testMainWritesHeredocWithNonGuessableDelimiterWhenMessagePresent() {
  local dir="${WORK_DIR}/main-present"
  mkdir -p "${dir}/addon-a"
  printf 'addon-a message\n' > "${dir}/addon-a/addon-testgrid-message.txt"
  GITHUB_OUTPUT="$(mktemp)"

  main "${dir}" "success"

  local output
  output="$(cat "${GITHUB_OUTPUT}")"
  local delim
  delim="$(head -n1 "${GITHUB_OUTPUT}" | sed 's/^message<<//')"

  assertNotEquals "EOF" "${delim}"
  assertEquals "message<<${delim}
addon-a message
${delim}" "${output}"
  rm -f "${GITHUB_OUTPUT}"
}

testResolveMessageReturnsArtifactMessageWhenPresent() {
  local dir="${WORK_DIR}/resolve-present"
  mkdir -p "${dir}/addon-a"
  printf 'addon-a message\n' > "${dir}/addon-a/addon-testgrid-message.txt"

  local result
  result="$(resolve_message "${dir}" "success" "https://example.test/run/1")"

  assertEquals "addon-a message" "${result}"
}

testResolveMessageReturnsEmptyWhenSkippedWithNoArtifacts() {
  local dir="${WORK_DIR}/resolve-skipped"
  mkdir -p "${dir}"

  local result
  result="$(resolve_message "${dir}" "skipped" "https://example.test/run/1")"

  assertEquals "" "${result}"
}

testResolveMessagePostsNoticeWhenSuccessWithNoArtifacts() {
  local dir="${WORK_DIR}/resolve-success-empty"
  mkdir -p "${dir}"

  local result
  result="$(resolve_message "${dir}" "success" "https://example.test/run/1")"

  assertNotEquals "" "${result}"
  assertContains "${result}" "success"
  assertContains "${result}" "https://example.test/run/1"
}

testResolveMessagePostsNoticeWhenFailureWithNoArtifacts() {
  local dir="${WORK_DIR}/resolve-failure-empty"
  mkdir -p "${dir}"

  local result
  result="$(resolve_message "${dir}" "failure" "https://example.test/run/2")"

  assertNotEquals "" "${result}"
  assertContains "${result}" "failure"
}

testResolveMessagePostsNoticeWithoutRunUrlWhenNotGiven() {
  local dir="${WORK_DIR}/resolve-failure-no-url"
  mkdir -p "${dir}"

  local result
  result="$(resolve_message "${dir}" "failure")"

  assertNotEquals "" "${result}"
  assertContains "${result}" "failure"
}

testResolveMessageReturnsEmptyWhenCancelledWithNoArtifacts() {
  local dir="${WORK_DIR}/resolve-cancelled-empty"
  mkdir -p "${dir}"

  local result
  result="$(resolve_message "${dir}" "cancelled")"

  assertEquals "" "${result}"
}

testMainWritesEmptyMessageOutputWhenCancelledWithNoArtifacts() {
  local dir="${WORK_DIR}/main-cancelled-empty"
  mkdir -p "${dir}"
  GITHUB_OUTPUT="$(mktemp)"

  main "${dir}" "cancelled"

  assertEquals "message=" "$(cat "${GITHUB_OUTPUT}")"
  rm -f "${GITHUB_OUTPUT}"
}

# shellcheck source=/dev/null
. shunit2
