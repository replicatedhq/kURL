#!/bin/bash
# Combines per-addon testgrid messages into a single PR comment body.

set -eo pipefail

function combine_testgrid_messages() {
  local dir="${1:?combine_testgrid_messages: directory argument required}"

  shopt -s nullglob
  local files=("${dir}"/*/addon-testgrid-message.txt)
  shopt -u nullglob

  local f
  for f in "${files[@]}"; do
    cat "$f"
    [ -z "$(tail -c1 "$f")" ] || echo
  done
}

function resolve_message() {
  local dir="${1:?resolve_message: directory argument required}"
  local test_addons_result="${2:?resolve_message: test-addons result required}"
  local run_url="${3:-}"

  local message=
  message="$(combine_testgrid_messages "$dir")"

  if [ -n "$message" ] || [ "$test_addons_result" = "skipped" ] || [ "$test_addons_result" = "cancelled" ]; then
    printf '%s' "$message"
    return 0
  fi

  # Legs were expected (check-addons found addons) but no per-addon message
  # was produced -- either the run genuinely failed/was cancelled before any
  # addon finished, or download-artifact failed transiently. Either way, the
  # PR promised a comment on completion; post a short notice instead of
  # silently posting nothing.
  local notice="⚠️ Testgrid add-on results were not available for this run (test-addons result: \`${test_addons_result}\`)."
  if [ -n "$run_url" ]; then
    notice="${notice} See the [workflow run](${run_url}) for details."
  fi
  printf '%s' "$notice"
}

function main() {
  local dir="${1:?usage: combine-testgrid-messages.sh <artifact-dir> <test-addons-result> [run-url]}"
  local test_addons_result="${2:?usage: combine-testgrid-messages.sh <artifact-dir> <test-addons-result> [run-url]}"
  local run_url="${3:-}"

  local message=
  message="$(resolve_message "$dir" "$test_addons_result" "$run_url")"

  if [ -z "$message" ]; then
    echo "message=" >> "$GITHUB_OUTPUT"
    return 0
  fi

  # Random delimiter: a fixed "EOF" could be forged by message content to inject output lines.
  local delim="EOF_$(openssl rand -hex 8)"
  {
    echo "message<<${delim}"
    printf '%s\n' "$message"
    echo "${delim}"
  } >> "$GITHUB_OUTPUT"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
