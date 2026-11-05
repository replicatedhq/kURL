import { test } from 'node:test';
import assert from 'node:assert/strict';
import { allAddonRunsDone, reportAddonCompletion, checkPullRequest } from './pullrequests.js';
import { stickyMarker, ADDON_STICKY_HEADER, addonDoneMarker, addonCompletionCommentMarker } from './rcrun.js';

const ADDON_MARKER = stickyMarker(ADDON_STICKY_HEADER);
const BOT_USER = { login: 'github-actions[bot]' };
const addonStickyComment = (body, id = 200, user = BOT_USER) => ({ id, body: `${body}\n${ADDON_MARKER}`, user });

test('allAddonRunsDone is false when a failed run is followed by a sibling still pending', () => {
  const failedRun = { pending_runs: 0, running_runs: 0, failure_count: 1, success_count: 0 };
  const pendingRun = { pending_runs: 1, running_runs: 0, failure_count: 0, success_count: 0 };
  assert.equal(allAddonRunsDone([failedRun, pendingRun]), false);
});

test('allAddonRunsDone is false when a run is still running', () => {
  const runningRun = { pending_runs: 0, running_runs: 1, failure_count: 0, success_count: 0 };
  assert.equal(allAddonRunsDone([runningRun]), false);
});

test('allAddonRunsDone is true once every run has no pending/running work left', () => {
  const runA = { pending_runs: 0, running_runs: 0, failure_count: 0, success_count: 1 };
  const runB = { pending_runs: 0, running_runs: 0, failure_count: 1, success_count: 0 };
  assert.equal(allAddonRunsDone([runA, runB]), true);
});

const runs = [{ success_count: 2, failure_count: 0, total_runs: 2 }];

const makeOctokit = ({ sticky, createComment, updateComment, existingComments = [], listComments }) => ({
  paginate: async (fn, params) => (listComments ? listComments(params) : existingComments),
  rest: {
    issues: {
      getComment: async () => ({ data: sticky }),
      createComment: createComment ?? (async () => {}),
      updateComment: updateComment ?? (async () => {}),
      listComments: 'listComments',
    },
  },
});

test('reportAddonCompletion does nothing when the prefix is already marked done', async () => {
  const sticky = addonStickyComment(`entries\n${addonDoneMarker('pr-1-abc')}`);
  let updateCalled = false;
  let createCalled = false;
  const octokit = makeOctokit({
    sticky,
    createComment: async () => { createCalled = true; },
    updateComment: async () => { updateCalled = true; },
  });

  await reportAddonCompletion(octokit, 'owner', 'repo', { number: 1, title: 't' }, sticky.id, 'pr-1-abc', runs);

  assert.equal(createCalled, false);
  assert.equal(updateCalled, false);
});

test('reportAddonCompletion posts the completion comment before writing the done marker', async () => {
  const sticky = addonStickyComment('entries');
  const calls = [];
  const octokit = makeOctokit({
    sticky,
    createComment: async () => { calls.push('createComment'); },
    updateComment: async ({ body }) => { calls.push('updateComment'); assert.match(body, /addon-done:pr-1-abc/); },
  });

  await reportAddonCompletion(octokit, 'owner', 'repo', { number: 1, title: 't' }, sticky.id, 'pr-1-abc', runs);

  assert.deepEqual(calls, ['createComment', 'updateComment']);
});

test('reportAddonCompletion skips re-posting when a completion comment for this prefix already exists', async () => {
  const sticky = addonStickyComment('entries');
  const calls = [];
  const existingComments = [{ id: 1, body: `some comment\n${addonCompletionCommentMarker('pr-1-abc')}` }];
  const octokit = makeOctokit({
    sticky,
    existingComments,
    createComment: async () => { calls.push('createComment'); },
    updateComment: async ({ body }) => { calls.push('updateComment'); assert.match(body, /addon-done:pr-1-abc/); },
  });

  await reportAddonCompletion(octokit, 'owner', 'repo', { number: 1, title: 't' }, sticky.id, 'pr-1-abc', runs);

  assert.deepEqual(calls, ['updateComment']);
});

test('reportAddonCompletion leaves the done marker unwritten when posting the comment fails', async () => {
  const sticky = addonStickyComment('entries');
  let updateCalled = false;
  const octokit = makeOctokit({
    sticky,
    createComment: async () => { throw new Error('rate limited'); },
    updateComment: async () => { updateCalled = true; },
  });

  await assert.rejects(
    () => reportAddonCompletion(octokit, 'owner', 'repo', { number: 1, title: 't' }, sticky.id, 'pr-1-abc', runs),
    /rate limited/
  );
  assert.equal(updateCalled, false);
});

const ADDON_RUN_LINE = 'Testgrid Run(s) Executing @ https://testgrid.kurl.sh/run/pr-1-abc1234-containerd-2.3.3-2026-10-07T17:47:28Z';

const makeFakeHttpClient = (responseBody) => ({
  get: async () => ({ readBody: async () => JSON.stringify(responseBody) }),
});

const makeCheckPullRequestOctokit = ({ prComments, createComment, updateComment, checksCreate }) => ({
  paginate: async () => prComments,
  rest: {
    issues: {
      listComments: 'listComments',
      getComment: async (params) => ({ data: prComments.find((c) => c.id === params.comment_id) }),
      createComment: createComment ?? (async () => {}),
      updateComment: updateComment ?? (async () => {}),
    },
    checks: {
      create: checksCreate ?? (async () => {}),
    },
  },
});

const pullRequest = { number: 1, title: 't', head: { sha: 'abc1234' }, labels: [] };

test('checkPullRequest reports completion when the addon-testgrid sticky batch is fully done', async () => {
  const sticky = addonStickyComment(ADDON_RUN_LINE, 300);
  const calls = [];
  const octokit = makeCheckPullRequestOctokit({
    prComments: [sticky],
    createComment: async () => { calls.push('createComment'); },
    updateComment: async ({ body }) => { calls.push('updateComment'); assert.match(body, /addon-done:/); },
  });
  const client = makeFakeHttpClient({
    total: 1,
    runs: [{ pending_runs: 0, running_runs: 0, failure_count: 0, success_count: 2, total_runs: 2 }],
  });

  await checkPullRequest(octokit, 'owner', 'repo', client)(pullRequest);

  assert.deepEqual(calls, ['createComment', 'updateComment']);
});

test('checkPullRequest never reports completion for a legacy (non-sticky) comment', async () => {
  const legacy = { id: 301, body: ADDON_RUN_LINE, user: BOT_USER };
  const calls = [];
  const octokit = makeCheckPullRequestOctokit({
    prComments: [legacy],
    createComment: async () => { calls.push('createComment'); },
    updateComment: async () => { calls.push('updateComment'); },
  });
  const client = makeFakeHttpClient({
    total: 1,
    runs: [{ pending_runs: 0, running_runs: 0, failure_count: 0, success_count: 2, total_runs: 2 }],
  });

  await checkPullRequest(octokit, 'owner', 'repo', client)(pullRequest);

  assert.deepEqual(calls, []);
});

test('checkPullRequest skips without querying testgrid when the entry ref is not a recognized addon prefix', async () => {
  const malformed = { id: 303, body: 'Testgrid Run(s) Executing @ https://testgrid.kurl.sh/run/not-a-valid-ref', user: BOT_USER };
  const calls = [];
  const octokit = makeCheckPullRequestOctokit({
    prComments: [malformed],
    createComment: async () => { calls.push('createComment'); },
    updateComment: async () => { calls.push('updateComment'); },
  });
  let clientCalled = false;
  const client = { get: async () => { clientCalled = true; return { readBody: async () => '{}' }; } };

  await checkPullRequest(octokit, 'owner', 'repo', client)(pullRequest);

  assert.equal(clientCalled, false);
  assert.deepEqual(calls, []);
});

test('checkPullRequest never reports completion while a sibling run in the batch is still pending', async () => {
  const sticky = addonStickyComment(ADDON_RUN_LINE, 302);
  const calls = [];
  const checksCreateCalls = [];
  const octokit = makeCheckPullRequestOctokit({
    prComments: [sticky],
    createComment: async () => { calls.push('createComment'); },
    updateComment: async () => { calls.push('updateComment'); },
    checksCreate: async (params) => { checksCreateCalls.push(params); },
  });
  const client = makeFakeHttpClient({
    total: 2,
    runs: [
      { pending_runs: 0, running_runs: 0, failure_count: 0, success_count: 1, total_runs: 1 },
      { pending_runs: 1, running_runs: 0, failure_count: 0, success_count: 0, total_runs: 1 },
    ],
  });

  await checkPullRequest(octokit, 'owner', 'repo', client)(pullRequest);

  assert.deepEqual(calls, []);
  assert.deepEqual(checksCreateCalls, []);
});

test('checkPullRequest ignores a forged run-line comment from a non-bot commenter', async () => {
  const forged = { id: 305, body: ADDON_RUN_LINE, user: { login: 'some-human' } };
  const calls = [];
  const checksCreateCalls = [];
  const octokit = makeCheckPullRequestOctokit({
    prComments: [forged],
    createComment: async () => { calls.push('createComment'); },
    updateComment: async () => { calls.push('updateComment'); },
    checksCreate: async (params) => { checksCreateCalls.push(params); },
  });
  let clientCalled = false;
  const client = { get: async () => { clientCalled = true; return { readBody: async () => '{}' }; } };

  await checkPullRequest(octokit, 'owner', 'repo', client)(pullRequest);

  assert.equal(clientCalled, false);
  assert.deepEqual(calls, []);
  assert.deepEqual(checksCreateCalls, []);
});

test('checkPullRequest ignores an addon ref prefix belonging to a different PR number', async () => {
  const otherPrRun = 'Testgrid Run(s) Executing @ https://testgrid.kurl.sh/run/pr-99-abc1234-containerd-2.3.3-2026-10-07T17:47:28Z';
  const sticky = addonStickyComment(otherPrRun, 306);
  const checksCreateCalls = [];
  const octokit = makeCheckPullRequestOctokit({
    prComments: [sticky],
    checksCreate: async (params) => { checksCreateCalls.push(params); },
  });
  let clientCalled = false;
  const client = { get: async () => { clientCalled = true; return { readBody: async () => '{}' }; } };

  await checkPullRequest(octokit, 'owner', 'repo', client)(pullRequest);

  assert.equal(clientCalled, false);
  assert.deepEqual(checksCreateCalls, []);
});

test('checkPullRequest never creates a success check-run while a sibling run in the batch is still failed', async () => {
  const sticky = addonStickyComment(ADDON_RUN_LINE, 304);
  const checksCreateCalls = [];
  const octokit = makeCheckPullRequestOctokit({
    prComments: [sticky],
    checksCreate: async (params) => { checksCreateCalls.push(params); },
  });
  const client = makeFakeHttpClient({
    total: 2,
    runs: [
      { pending_runs: 0, running_runs: 0, failure_count: 0, success_count: 1, total_runs: 1 },
      { pending_runs: 0, running_runs: 0, failure_count: 1, success_count: 0, total_runs: 1 },
    ],
  });

  await checkPullRequest(octokit, 'owner', 'repo', client)(pullRequest);

  assert.equal(checksCreateCalls.length, 1);
  assert.equal(checksCreateCalls[0].conclusion, 'failure');
});

test('checkPullRequest never creates a success check-run for a stale sticky entry after a force-push', async () => {
  const staleRunLine = 'Testgrid Run(s) Executing @ https://testgrid.kurl.sh/run/pr-1-old0000-containerd-2.3.3-2026-10-07T17:47:28Z';
  const sticky = addonStickyComment(staleRunLine, 307);
  const checksCreateCalls = [];
  let clientCalled = false;
  const octokit = makeCheckPullRequestOctokit({
    prComments: [sticky],
    checksCreate: async (params) => { checksCreateCalls.push(params); },
  });
  const client = { get: async () => { clientCalled = true; return { readBody: async () => '{}' }; } };

  await checkPullRequest(octokit, 'owner', 'repo', client)(pullRequest);

  assert.equal(clientCalled, false);
  assert.deepEqual(checksCreateCalls, []);
});
