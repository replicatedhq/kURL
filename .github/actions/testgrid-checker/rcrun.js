// RC-run (testgrid-pr label workflow) result tracking for the testgrid-checker.
//
// The testgrid-pr workflow appends one queue entry per run into a single
// sticky PR comment (marocchino/sticky-pull-request-comment, header
// `testgrid-pr`). This module lets the 15-min checker cron:
//   * find that sticky comment and the latest queued run entry in it,
//   * append one line per finished leg (scenario x OS instance) as they
//     complete, deduped via hidden <!--leg:<instanceId>--> markers, and
//   * when the run completes, produce a final summary line plus the body for
//     a NEW PR comment (comment edits don't notify; completions should).
// Legacy addon runs keep their own comment/check-run flow in pullrequests.js.

export const STICKY_HEADER = 'testgrid-pr';

// marocchino/sticky-pull-request-comment hides this marker at the end of the
// comment body and uses it to find the comment again on later appends. Our
// writes must preserve it, so new content is inserted just before it.
export const stickyMarker = (header = STICKY_HEADER) =>
  `<!-- Sticky Pull Request Comment${header} -->`;

// Matches every run-entry line the testgrid-pr workflow appends to the sticky
// comment (and the legacy per-comment lines the test-addon flow posts), e.g.
//   Testgrid Run(s) Executing @ https://testgrid.kurl.sh/run/pr-6176-3b80852-...
// capturing the FULL ref after /run/.
const RUN_LINE_RE = /Testgrid Run\(s\) Executing @\W+https:\/\/testgrid\.kurl\.sh\/run\/([^\s)]+)/g;

// RC runs queue with an uppercase PR- prefixed ref (get-tag in
// testgrid-pr.yaml); addon runs use lowercase pr-<number>-<sha>.
export const isRCRef = (ref) => ref.startsWith('PR-');

// The testgrid API stores run refs lowercased and matches searchRef
// case-sensitively against them (verified live: searchRef=PR-... finds
// nothing, searchRef=pr-... finds the run), so RC refs must be lowercased
// before lookup. Display-case ids keep working on the /run/{id} endpoint.
export const rcSearchRef = (ref) => ref.toLowerCase();

// The addon flow watches a ref PREFIX so one queued batch (multiple runs
// sharing the prefix) resolves together; identical to the extraction the old
// per-comment regex performed.
export const addonRefPrefix = (ref) => (ref.match(/^pr-\d+-\w+/) || [])[0] || '';

// Latest run entry wins (same "last comment wins" semantics the addon flow
// always had): comments in ascending id order, then line order within a body.
export const findLastRunEntry = (comments) => {
  let last = null;
  for (const comment of comments) {
    if (!comment.body) continue;
    for (const match of comment.body.matchAll(RUN_LINE_RE)) {
      last = { ref: match[1], comment };
    }
  }
  return last;
};

export const extractReportedLegIds = (body) =>
  new Set([...body.matchAll(/<!--leg:([^>]+)-->/g)].map((m) => m[1]));

export const legFinished = (instance) =>
  instance.finishedAt || instance.isSkipped || instance.isUnsupported || instance.cancelledAt;

export const legFailed = (instance) =>
  !instance.isSuccess && !instance.isSkipped && !instance.isUnsupported && !instance.cancelledAt;

// One status line per leg (a scenario x OS instance from the testgrid API),
// tagged with a hidden marker the next tick dedupes against.
export const buildLegLine = (instance) => {
  const os = [instance.osName, instance.osVersion].filter(Boolean).join(' ') || 'unknown OS';
  let status = '❌';
  if (instance.isSuccess && !instance.isSkipped && !instance.isUnsupported && !instance.cancelledAt) {
    status = '✅';
  } else if (instance.cancelledAt) {
    status = '✂️ cancelled';
  } else if (instance.isUnsupported) {
    status = '⏭️ unsupported';
  } else if (instance.isSkipped) {
    status = '⏭️ skipped';
  }
  const reason = instance.failureReason ? ` — \`${instance.failureReason}\`` : '';
  return `- ${status} **${instance.testName}** — ${os}${reason} <!--leg:${instance.id}-->`;
};

// Final line appended to the sticky once every run under the ref is done; the
// hidden done marker makes later ticks skip the PR.
export const buildSummaryLine = (ref, { passed, failed, skipped }) =>
  `- 🏁 Run \`${ref}\` completed — ${passed} ✅ · ${failed} ❌ · ${skipped} skipped/unsupported/cancelled <!--done:${ref}-->`;

// Insert new content just before the sticky marker (which the sticky action
// keeps at the very end of the comment body). Falls back to plain append if
// the marker is missing (e.g. a hand-crafted comment).
export const appendToSticky = (body, addition) => {
  const marker = stickyMarker();
  const idx = body.lastIndexOf(marker);
  if (idx === -1) {
    return `${body}\n${addition}`;
  }
  return `${body.slice(0, idx)}${addition}\n${body.slice(idx)}`;
};

export const buildCompletionCommentBody = (ref, { passed, failed, skipped }, failedLegs) => {
  const headline = failed > 0 ? '❌ failed' : '✅ passed';
  const lines = [
    `### 🏁 Testgrid RC run ${headline}`,
    `- Result: **${passed} passed, ${failed} failed, ${skipped} skipped/unsupported/cancelled** — [run details](https://testgrid.kurl.sh/run/${ref})`,
  ];
  if (failedLegs && failedLegs.length > 0) {
    lines.push('', 'Failed legs (full details in the sticky testgrid comment):');
    for (const line of failedLegs.slice(0, 10)) {
      lines.push(line.replace(/ <!--leg:[^>]+-->$/, ''));
    }
    if (failedLegs.length > 10) {
      lines.push(`… and ${failedLegs.length - 10} more`);
    }
  }
  return lines.join('\n');
};
