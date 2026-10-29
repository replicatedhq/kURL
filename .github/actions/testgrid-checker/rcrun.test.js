import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  stickyMarker,
  isRCRef,
  rcSearchRef,
  addonRefPrefix,
  findLastRunEntry,
  extractReportedLegIds,
  buildLegLine,
  buildSummaryLine,
  appendToSticky,
  buildCompletionCommentBody,
  legFinished,
  legFailed,
} from './rcrun.js';

const MARKER = stickyMarker();

const stickyComment = (body, id = 100) => ({ id, body: `${body}\n${MARKER}` });
const plainComment = (body, id = 50) => ({ id, body });

const queueEntry = (ref) =>
  `### 🧪 Testgrid RC run — \`v2026.10.13-0-rc-pr123-abc1234\`\n- Testgrid Run(s) Executing @ https://testgrid.kurl.sh/run/${ref}`;

test('findLastRunEntry picks the last line inside the sticky comment', () => {
  const comments = [
    plainComment(
      'Testgrid Run(s) Executing @ https://testgrid.kurl.sh/run/pr-99-abcdef-2026-01-01T00:00:00Z',
      10
    ),
    stickyComment(
      `${queueEntry('PR-v1-rc-pr123-aaa-2026-01-01T00:00:00Z')}\n${queueEntry('PR-v1-rc-pr123-bbb-2026-01-02T00:00:00Z')}`,
      20
    ),
  ];
  const entry = findLastRunEntry(comments);
  assert.equal(entry.ref, 'PR-v1-rc-pr123-bbb-2026-01-02T00:00:00Z');
  assert.equal(entry.comment.id, 20);
});

test('findLastRunEntry falls back to a standalone legacy addon comment', () => {
  const comments = [
    plainComment(
      'Testgrid Run(s) Executing @ https://testgrid.kurl.sh/run/pr-6176-3b80852-containerd-2.3.3-k8s-ctrd-2026-10-07T17:47:28Z',
      10
    ),
  ];
  const entry = findLastRunEntry(comments);
  assert.equal(entry.ref, 'pr-6176-3b80852-containerd-2.3.3-k8s-ctrd-2026-10-07T17:47:28Z');
  assert.equal(entry.comment.id, 10);
});

test('findLastRunEntry returns null when nothing matches', () => {
  assert.equal(findLastRunEntry([{ id: 1, body: 'just a human comment' }]), null);
  assert.equal(findLastRunEntry([{ id: 1, body: null }]), null);
  assert.equal(findLastRunEntry([]), null);
});

test('isRCRef distinguishes uppercase RC refs from lowercase addon refs', () => {
  assert.equal(isRCRef('PR-v2026.10.13-0-rc-pr6202-3ca3434-2026-10-15T00:17:23Z'), true);
  assert.equal(isRCRef('pr-6176-3b80852'), false);
});

test('rcSearchRef lowercases the ref so the case-sensitive API finds it', () => {
  assert.equal(
    rcSearchRef('PR-v2026.10.13-0-rc-pr6202-3ca3434-2026-10-15T00:17:23Z'),
    'pr-v2026.10.13-0-rc-pr6202-3ca3434-2026-10-15t00:17:23z'
  );
});

test('addonRefPrefix extracts the same prefix the old per-comment regex did', () => {
  assert.equal(
    addonRefPrefix('pr-6176-3b80852-containerd-2.3.3-k8s-ctrd-2026-10-07T17:47:28Z'),
    'pr-6176-3b80852'
  );
  assert.equal(addonRefPrefix('pr-3569-3eb59f9'), 'pr-3569-3eb59f9');
  assert.equal(addonRefPrefix('PR-v1-rc-pr1-abc-2026-01-01T00:00:00Z'), '');
});

test('extractReportedLegIds collects ids from hidden leg markers', () => {
  const body = `- ✅ **A** — Ubuntu 22.04 <!--leg:i1-->\n- ❌ **B** — RHEL 9 <!--leg:i2-->`;
  assert.deepEqual(extractReportedLegIds(body), new Set(['i1', 'i2']));
  assert.deepEqual(extractReportedLegIds('no markers'), new Set());
});

test('buildLegLine renders a passing leg without a reason', () => {
  const line = buildLegLine({
    id: 'i1',
    testName: 'Fresh install',
    osName: 'Ubuntu',
    osVersion: '22.04',
    isSuccess: true,
  });
  assert.match(line, /^- ✅ \*\*Fresh install\*\* — Ubuntu 22\.04 <!--leg:i1-->$/);
});

test('buildLegLine renders a failed leg with its failure reason', () => {
  const line = buildLegLine({
    id: 'i2',
    testName: 'Upgrade',
    osName: 'Amazon Linux',
    osVersion: '2.0',
    isSuccess: false,
    failureReason: 'kurl_upgrade',
  });
  assert.match(line, /^- ❌ \*\*Upgrade\*\* — Amazon Linux 2\.0 — `kurl_upgrade` <!--leg:i2-->$/);
});

test('buildLegLine classifies cancelled over skipped, then unsupported', () => {
  const cancelled = buildLegLine({ id: 'i3', testName: 'T', osName: 'X', osVersion: '1', isSkipped: true, cancelledAt: '2026-01-01T00:00:00Z' });
  assert.match(cancelled, /^- ✂️ cancelled \*\*T\*\* — X 1 <!--leg:i3-->$/);
  const unsupported = buildLegLine({ id: 'i4', testName: 'T', osName: 'X', osVersion: '1', isUnsupported: true });
  assert.match(unsupported, /^- ⏭️ unsupported \*\*T\*\* — X 1 <!--leg:i4-->$/);
  const skipped = buildLegLine({ id: 'i5', testName: 'T', osName: 'X', osVersion: '1', isSkipped: true });
  assert.match(skipped, /^- ⏭️ skipped \*\*T\*\* — X 1 <!--leg:i5-->$/);
});

test('buildLegLine handles missing OS metadata', () => {
  const line = buildLegLine({ id: 'i6', testName: 'T', isSuccess: true });
  assert.match(line, /— unknown OS <!--leg:i6-->$/);
});

test('legFinished and legFailed gate which instances get reported', () => {
  assert.ok(legFinished({ finishedAt: '2026-01-01T00:00:00Z' }));
  assert.ok(legFinished({ isSkipped: true }));
  assert.ok(!legFinished({}));
  assert.ok(legFailed({ isSuccess: false }));
  assert.ok(!legFailed({ isSuccess: true }));
  assert.ok(!legFailed({ isSuccess: false, isUnsupported: true }));
  assert.ok(!legFailed({ isSuccess: false, cancelledAt: '2026-01-01T00:00:00Z' }));
});

test('buildSummaryLine carries the done marker for the ref', () => {
  const line = buildSummaryLine('PR-v1-rc-pr1-abc-2026-01-01T00:00:00Z', { passed: 51, failed: 2, skipped: 3 });
  assert.match(line, /^- 🏁 Run `PR-v1-rc-pr1-abc-2026-01-01T00:00:00Z` completed — 51 ✅ · 2 ❌ · 3 skipped\/unsupported\/cancelled <!--done:PR-v1-rc-pr1-abc-2026-01-01T00:00:00Z-->$/);
});

test('appendToSticky inserts before the marker and keeps the marker last', () => {
  const body = stickyComment('### entry one\n- line a').body;
  const result = appendToSticky(body, '- line b');
  assert.ok(result.endsWith(MARKER));
  assert.ok(result.indexOf('- line b') < result.indexOf(MARKER));
  assert.ok(result.includes('- line a'));
});

test('appendToSticky appends plainly when the marker is missing', () => {
  const result = appendToSticky('no marker here', '- line b');
  assert.equal(result, 'no marker here\n- line b');
});

test('buildCompletionCommentBody announces success without a leg list', () => {
  const body = buildCompletionCommentBody('ref-1', { passed: 5, failed: 0, skipped: 0 }, []);
  assert.match(body, /### 🏁 Testgrid RC run ✅ passed/);
  assert.match(body, /\*\*5 passed, 0 failed, 0 skipped\/unsupported\/cancelled\*\*/);
  assert.match(body, /\[run details\]\(https:\/\/testgrid\.kurl\.sh\/run\/ref-1\)/);
  assert.doesNotMatch(body, /Failed legs/);
});

test('buildCompletionCommentBody lists failed legs with markers stripped', () => {
  const legs = [buildLegLine({ id: 'i1', testName: 'A', osName: 'U', osVersion: '22', isSuccess: false, failureReason: 'kurl_install' })];
  const body = buildCompletionCommentBody('ref-1', { passed: 3, failed: 1, skipped: 0 }, legs);
  assert.match(body, /### 🏁 Testgrid RC run ❌ failed/);
  assert.match(body, /- ❌ \*\*A\*\* — U 22 — `kurl_install`$/m);
  assert.doesNotMatch(body, /<!--leg:/);
});

test('buildCompletionCommentBody truncates long failed-leg lists', () => {
  const legs = Array.from({ length: 12 }, (_, i) =>
    buildLegLine({ id: `i${i}`, testName: `T${i}`, osName: 'U', osVersion: '22', isSuccess: false })
  );
  const body = buildCompletionCommentBody('ref-1', { passed: 0, failed: 12, skipped: 0 }, legs);
  assert.match(body, /… and 2 more/);
  assert.equal(body.match(/- ❌/g).length, 10);
});
