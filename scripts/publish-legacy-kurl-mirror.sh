#!/usr/bin/env bash
set -euo pipefail

[[ "${GITHUB_REPOSITORY,,}" == replicatedhq/kurl && "$GITHUB_EVENT_NAME" == workflow_dispatch ]]
case "${BACKFILL_PHASE:-}" in
  promote-mirror|stage-mirror|reconcile-mirror|reconcile-after-expiry|restore-mirror) ;;
  *) echo 'Specify a supported legacy kURL mirror operation.' >&2; exit 1 ;;
esac
[[ "${BACKFILL_PLAN_SHA256:-}" =~ ^[a-f0-9]{64}$ ]]
[[ "${BACKFILL_PLAN_B64:-}" =~ ^[A-Za-z0-9+/]+={0,2}$ ]]
[[ "${#BACKFILL_PLAN_B64}" -le 32000 ]]

work="$RUNNER_TEMP/legacy-kurl-mirror"
plan="$work/plan.json"
publisher=scripts/publish-legacy-kurl.py

check_plan() {
  printf '%s  %s\n' "$BACKFILL_PLAN_SHA256" "$plan" | sha256sum --check --strict
  python3 "$publisher" check-plan --plan "$plan"
}

case "${1:-}" in
  verify)
    mkdir -m 700 "$work"
    printf '%s' "$BACKFILL_PLAN_B64" | base64 --decode > "$plan"
    check_plan
    ;;
  apply)
    check_plan
    if [[ "$BACKFILL_PHASE" == restore-mirror ]]; then
      key="$(jq -er '.mirror_key' "$plan")"
      original_version="$(jq -er '.original.version_id' "$plan")"
      [[ -n "$original_version" && "$original_version" != null ]]
      original="$work/original.tar.gz"
      aws s3api get-object --no-cli-pager --bucket kurl-sh --key "$key" --version-id "$original_version" "$original" > "$work/original-s3-receipt.json"
      python3 "$publisher" restore-mirror --plan "$plan" --original "$original"
    else
      python3 "$publisher" "$BACKFILL_PHASE" --plan "$plan"
    fi
    ;;
  *)
    echo 'Specify verify or apply.' >&2
    exit 1
    ;;
esac
