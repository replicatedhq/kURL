import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  stickyMarker,
  isRCRef,
  rcSearchRef,
  addonRefPrefix,
  findLastRunEntry,
  TRUSTED_RUN_LINE_LOGIN,
  extractReportedLegIds,
  buildLegLine,
  buildSummaryLine,
  appendToSticky,
  buildCompletionCommentBody,
  legFinished,
  legFailed,
  ADDON_STICKY_HEADER,
  addonDoneMarker,
  isAddonDone,
  buildAddonCompletionCommentBody,
  addonCompletionCommentMarker,
} from './rcrun.js';

const MARKER = stickyMarker();
const ADDON_MARKER = stickyMarker(ADDON_STICKY_HEADER);
const BOT_USER = { login: 'github-actions[bot]' };

const stickyComment = (body, id = 100, user = BOT_USER) => ({ id, body: `${body}\n${MARKER}`, user });
const addonStickyComment = (body, id = 200, user = BOT_USER) => ({ id, body: `${body}\n${ADDON_MARKER}`, user });
const plainComment = (body, id = 50, user = BOT_USER) => ({ id, body, user });

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

test('findLastRunEntry ignores a forged run line posted by a non-bot commenter', () => {
  const forged = plainComment(
    'Testgrid Run(s) Executing @ https://testgrid.kurl.sh/run/pr-6176-eeeeeee-containerd-2.3.3-2026-10-07T17:47:28Z',
    10,
    { login: 'some-human' }
  );
  assert.equal(findLastRunEntry([forged]), null);
});

test('findLastRunEntry still trusts a real run line from the bot alongside a forged one', () => {
  const forged = plainComment(
    'Testgrid Run(s) Executing @ https://testgrid.kurl.sh/run/pr-6176-eeeeeee-containerd-2.3.3-2026-10-07T17:47:28Z',
    10,
    { login: 'some-human' }
  );
  const legit = plainComment(
    'Testgrid Run(s) Executing @ https://testgrid.kurl.sh/run/pr-6176-aaaaaaa-containerd-2.3.3-2026-10-07T17:48:00Z',
    20
  );
  const entry = findLastRunEntry([forged, legit]);
  assert.equal(entry.ref, 'pr-6176-aaaaaaa-containerd-2.3.3-2026-10-07T17:48:00Z');
});

test('TRUSTED_RUN_LINE_LOGIN is the default GITHUB_TOKEN actor, not the checker app', () => {
  assert.equal(TRUSTED_RUN_LINE_LOGIN, 'github-actions[bot]');
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

test('stickyMarker distinguishes the addon-testgrid header from the RC default', () => {
  assert.notEqual(ADDON_MARKER, MARKER);
  assert.ok(ADDON_MARKER.includes('addon-testgrid'));
});

test('findLastRunEntry finds an addon ref living inside the addon-testgrid sticky comment', () => {
  const comments = [
    addonStickyComment(
      'Testgrid Run(s) Executing @ https://testgrid.kurl.sh/run/pr-6176-3b80852-containerd-2.3.3-k8s-ctrd-2026-10-07T17:47:28Z\n' +
      'Testgrid Run(s) Executing @ https://testgrid.kurl.sh/run/pr-6176-3b80852-flannel-0.26.1-2026-10-07T17:48:00Z'
    ),
  ];
  const entry = findLastRunEntry(comments);
  assert.equal(entry.ref, 'pr-6176-3b80852-flannel-0.26.1-2026-10-07T17:48:00Z');
  assert.ok(entry.comment.body.includes(ADDON_MARKER));
});

test('findLastRunEntry prefers the entry matching the current head sha over a later-created sibling sticky', () => {
  const comments = [
    addonStickyComment(
      'Testgrid Run(s) Executing @ https://testgrid.kurl.sh/run/pr-6176-aaaaaaa-containerd-2.3.3-2026-10-07T17:47:28Z',
      10
    ),
    stickyComment(
      queueEntry('PR-v1-rc-pr6176-bbbbbbb-2026-10-07T18:00:00Z'),
      20
    ),
  ];

  const entry = findLastRunEntry(comments, 'aaaaaaa0000000000000000000000000000000');
  assert.equal(entry.ref, 'pr-6176-aaaaaaa-containerd-2.3.3-2026-10-07T17:47:28Z');
  assert.equal(entry.comment.id, 10);
});

test('findLastRunEntry returns the matching RC entry when no addon entry matches the head sha', () => {
  const comments = [
    addonStickyComment(
      'Testgrid Run(s) Executing @ https://testgrid.kurl.sh/run/pr-6176-bbbbbbb-containerd-2.3.3-2026-10-07T17:47:28Z',
      10
    ),
    stickyComment(
      queueEntry('PR-v1-rc-pr6176-aaaaaaa-2026-10-07T18:00:00Z'),
      20
    ),
  ];

  const entry = findLastRunEntry(comments, 'aaaaaaa0000000000000000000000000000000');
  assert.equal(entry.ref, 'PR-v1-rc-pr6176-aaaaaaa-2026-10-07T18:00:00Z');
  assert.equal(entry.comment.id, 20);
});

test('findLastRunEntry prefers the addon entry over an RC entry when both match the current head sha', () => {
  const comments = [
    addonStickyComment(
      'Testgrid Run(s) Executing @ https://testgrid.kurl.sh/run/pr-6176-aaaaaaa-containerd-2.3.3-2026-10-07T17:47:28Z',
      10
    ),
    stickyComment(
      queueEntry('PR-v1-rc-pr6176-aaaaaaa-2026-10-07T18:00:00Z'),
      20
    ),
  ];

  const entry = findLastRunEntry(comments, 'aaaaaaa0000000000000000000000000000000');
  assert.equal(entry.ref, 'pr-6176-aaaaaaa-containerd-2.3.3-2026-10-07T17:47:28Z');
  assert.equal(entry.comment.id, 10);
});

test('findLastRunEntry returns null after a force-push when no entry matches the new head sha', () => {
  const comments = [
    addonStickyComment(
      'Testgrid Run(s) Executing @ https://testgrid.kurl.sh/run/pr-6176-aaaaaaa-containerd-2.3.3-2026-10-07T17:47:28Z',
      10
    ),
    stickyComment(
      queueEntry('PR-v1-rc-pr6176-bbbbbbb-2026-10-07T18:00:00Z'),
      20
    ),
  ];

  const entry = findLastRunEntry(comments, 'ccccccc0000000000000000000000000000000');
  assert.equal(entry, null);
});

test('findLastRunEntry still prefers a more recent legacy standalone comment over an older addon sticky', () => {
  const comments = [
    addonStickyComment(
      'Testgrid Run(s) Executing @ https://testgrid.kurl.sh/run/pr-6176-3b80852-containerd-2.3.3-2026-10-07T17:47:28Z',
      10
    ),
    plainComment(
      'Testgrid Run(s) Executing @ https://testgrid.kurl.sh/run/pr-6176-aaaaaaa-containerd-2.3.4-2026-10-08T00:00:00Z',
      20
    ),
  ];
  const entry = findLastRunEntry(comments);
  assert.equal(entry.ref, 'pr-6176-aaaaaaa-containerd-2.3.4-2026-10-08T00:00:00Z');
  assert.equal(entry.comment.id, 20);
});

test('addonDoneMarker/isAddonDone dedupe completion reporting per prefix', () => {
  const prefix = 'pr-6176-3b80852';
  const body = addonStickyComment('entries here').body;
  assert.equal(isAddonDone(body, prefix), false);
  const updated = appendToSticky(body, addonDoneMarker(prefix), ADDON_STICKY_HEADER);
  assert.equal(isAddonDone(updated, prefix), true);
  assert.equal(isAddonDone(updated, 'pr-6176-other'), false);
  assert.ok(updated.endsWith(ADDON_MARKER));
  assert.ok(updated.indexOf(addonDoneMarker(prefix)) < updated.indexOf(ADDON_MARKER));
});

test('buildAddonCompletionCommentBody announces a passing addon run', () => {
  const body = buildAddonCompletionCommentBody('pr-6176-3b80852', { passed: 4, failed: 0, skipped: 1 });
  assert.match(body, /✅ passed/);
  assert.match(body, /\*\*4 passed, 0 failed, 1 skipped\*\*/);
  assert.match(body, /`pr-6176-3b80852`/);
  assert.ok(body.includes(addonCompletionCommentMarker('pr-6176-3b80852')));
});

test('buildAddonCompletionCommentBody announces a failing addon run', () => {
  const body = buildAddonCompletionCommentBody('pr-6176-3b80852', { passed: 2, failed: 3, skipped: 0 });
  assert.match(body, /❌ failed/);
  assert.match(body, /\*\*2 passed, 3 failed, 0 skipped\*\*/);
});
