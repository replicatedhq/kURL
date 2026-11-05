#!/bin/bash

WORKFLOW_FILES="./.github/workflows/test-addon-pr.yaml ./.github/workflows/test-addon.yaml"

testRunBlocksDoNotInterpolateStepsOrEventOutputsDirectly() {
    local file
    for file in ${WORKFLOW_FILES}; do
        local offenders
        offenders="$(awk '
            /^[[:space:]]*run: \|/ { inrun=1; indent=-1; next }
            inrun {
                if (indent < 0) {
                    match($0, /^[[:space:]]*/)
                    indent = RLENGTH
                }
                line_indent_match = match($0, /^[[:space:]]*/)
                line_indent = RLENGTH
                if ($0 !~ /^[[:space:]]*$/ && line_indent < indent) {
                    inrun = 0
                    next
                }
                print
            }
        ' "${file}" | grep -E '\$\{\{[[:space:]]*(steps\.|github\.event\.)')"

        assertEquals "found unsafe \${{ steps.*/github.event.* }} interpolation inside a run: block in ${file}: ${offenders}" \
            "" "${offenders}"
    done
}

testPostCommentJobSkipsWhenTestAddonsIsCancelled() {
    local if_line
    if_line="$(awk '/^  post-comment:/{found=1} found && /^    if:/{print; exit}' ./.github/workflows/test-addon-pr.yaml)"

    local excludes_cancelled=0
    printf '%s' "${if_line}" | grep -qF "needs.test-addons.result != 'cancelled'" && excludes_cancelled=1

    assertEquals "post-comment job's if: must exclude a cancelled test-addons result, got: ${if_line}" \
        1 "${excludes_cancelled}"
}

testExistingStickyCommentFetchIsScopedToBotAuthor() {
    local jq_line
    jq_line="$(grep -A10 "Fetch existing sticky comment" ./.github/workflows/test-addon-pr.yaml | grep -- '--jq')"

    local found=0
    printf '%s' "${jq_line}" | grep -qF 'select(.user.login == "github-actions[bot]")' && found=1

    assertEquals "jq filter for the existing sticky comment must select the bot's own comments only, got: ${jq_line}" \
        1 "${found}"
}

# shellcheck source=/dev/null
. shunit2
