import * as core from '@actions/core';
import { HttpClient } from '@actions/http-client';
import { GraphqlResponseError } from '@octokit/graphql';
import { getLoginForApp, handleError } from './github.js';
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
  ADDON_STICKY_HEADER,
  addonDoneMarker,
  isAddonDone,
  buildAddonCompletionCommentBody,
  addonCompletionCommentMarker,
} from './rcrun.js';

const httpClient = new HttpClient();
const TESTGRID_API = 'https://api.testgrid.kurl.sh/api/v1';

export const allAddonRunsDone = runs =>
  runs.every(run => !(run.pending_runs > 0) && !(run.running_runs > 0));

export const checkPullRequest = (octokit, owner, repo, client = httpClient) => async pullRequest => {
  const prNumber = pullRequest.number;
  const prTitle = pullRequest.title;
  console.log(`PR "${prTitle}" #${prNumber}: checking`);

  // Paginate: noisy PRs (the very thing the sticky comment fixes) can hold
  // hundreds of comments, and the sticky must be findable regardless.
  const thisPrComments = await octokit.paginate(octokit.rest.issues.listComments, {
    owner,
    repo,
    issue_number: prNumber,
  });

  // The run entry to watch is the one matching this tick's current head sha
  // where possible, falling back to the LATEST in document order: either a
  // standalone comment (legacy test-addon flow) or a line inside the single
  // sticky comment the testgrid-pr workflow appends to.
  const lastEntry = findLastRunEntry(thisPrComments, pullRequest.head.sha);
  if (!lastEntry) {
    console.log(`PR "${prTitle}" #${prNumber}: no testgrid run found`);
    return;
  }

  if (isRCRef(lastEntry.ref)) {
    await checkRCRun(octokit, owner, repo, pullRequest, lastEntry, client);
    return;
  }

  const lastTestgridCommentPrefix = addonRefPrefix(lastEntry.ref);
  if (!lastTestgridCommentPrefix) {
    console.log(`PR "${prTitle}" #${prNumber}: entry ref "${lastEntry.ref}" is not a recognized addon prefix, skipping`);
    return;
  }
  if (!lastTestgridCommentPrefix.startsWith(`pr-${prNumber}-`)) {
    console.log(`PR "${prTitle}" #${prNumber}: entry ref prefix "${lastTestgridCommentPrefix}" does not belong to this PR, skipping`);
    return;
  }

  const response = await client.get(`https://api.testgrid.kurl.sh/api/v1/runs?searchRef=${encodeURIComponent(lastTestgridCommentPrefix)}`);
  const responseBody = JSON.parse(await response.readBody());

  if (responseBody.total !== 0) {
    if (!allAddonRunsDone(responseBody.runs)) {
      console.log(`PR "${prTitle}" #${prNumber}: has pending or running runs`);
      return;
    }
    const passing = !responseBody.runs.some(run => run.failure_count > 0);
    console.log(`PR "${prTitle}" #${prNumber}: ${passing ? 'is passing' : 'has failed runs'}`);

    await octokit.rest.checks.create({
      owner,
      repo,
      name: 'testgrid-checker',
      head_sha: pullRequest.head.sha,
      status: 'completed',
      conclusion: passing ? 'success' : 'failure',
    });
    if (passing) {
      if (pullRequest.labels.some(label => label.name === 'auto-merge')) {
        console.log(`PR "${prTitle}" #${prNumber}: is passing and has auto-merge label, approving and enabling automerge`);
        try {
          await Promise.allSettled([
            approvePullRequest(octokit, owner, repo, pullRequest, "Automation (testgrid-checker): passing"),
            enablePullRequestAutomerge(octokit, pullRequest),
            mergePullRequest(octokit, owner, repo, pullRequest),
          ]);
        } catch (error) {
          console.log("ERROR", error);
        }
      } else {
        console.log(`PR "${prTitle}" #${prNumber}: is passing but not labeled for auto-merge`);
      }
    }
    console.log(`PR "${prTitle}" #${prNumber}: is done`);

    const isSticky = lastEntry.comment.body.includes(stickyMarker(ADDON_STICKY_HEADER));
    if (isSticky) {
      await reportAddonCompletion(octokit, owner, repo, pullRequest, lastEntry.comment.id, lastTestgridCommentPrefix, responseBody.runs);
    }
  } else {
    core.warning(
      `WARNING: PR "${prTitle}" #${prNumber}: no testgrid run found despite finding comment`
    );
  }
};

// RC runs (testgrid-pr label workflow, refs like PR-v2026.10.13-0-rc-pr123-abc1234-<ts>)
// get progress reported INTO the sticky comment instead of a check run: every
// tick appends lines for legs that finished since the last tick, and on
// completion appends a final summary line and posts a NEW comment so
// watchers get notified (comment edits don't notify). Deliberately no
// check-run and no automerge here — that machinery stays addon-only.
const checkRCRun = async (octokit, owner, repo, pullRequest, entry, client = httpClient) => {
  const prNumber = pullRequest.number;
  const prTitle = pullRequest.title;
  const ref = entry.ref;
  const stickyRef = entry.comment;

  if (!stickyRef.body.includes(stickyMarker())) {
    console.log(`PR "${prTitle}" #${prNumber}: RC entry ${ref} found outside the sticky comment, skipping`);
    return;
  }
  if (stickyRef.body.includes(`<!--done:${ref}-->`)) {
    console.log(`PR "${prTitle}" #${prNumber}: RC run ${ref} already completed, nothing to do`);
    return;
  }

  // Re-read the sticky body right before read-modify-write so a queue entry
  // the workflow appended since listComments isn't clobbered below.
  const { data: sticky } = await octokit.rest.issues.getComment({ owner, repo, comment_id: stickyRef.id });
  if (sticky.body.includes(`<!--done:${ref}-->`)) {
    console.log(`PR "${prTitle}" #${prNumber}: RC run ${ref} already completed (fresh read), nothing to do`);
    return;
  }

  const response = await client.get(`${TESTGRID_API}/runs?searchRef=${encodeURIComponent(rcSearchRef(ref))}`);
  const responseBody = JSON.parse(await response.readBody());
  const runs = responseBody.runs || [];
  if (runs.length === 0) {
    core.warning(
      `WARNING: PR "${prTitle}" #${prNumber}: no testgrid run found despite finding RC entry ${ref}`
    );
    return;
  }

  let pending = 0;
  let running = 0;
  for (const run of runs) {
    pending += run.pending_runs || 0;
    running += run.running_runs || 0;
  }
  const done = pending === 0 && running === 0;

  const reportedIds = extractReportedLegIds(sticky.body);
  const newLines = [];
  const failedLegs = [];

  for (const run of runs) {
    // POST only: the run detail endpoint returns 405 on GET (mirrors
    // bin/verify-testgrid-run.sh, which curls it with a `{}` body).
    const detail = await client.post(`${TESTGRID_API}/run/${encodeURIComponent(run.id)}`, "{}");
    const instances = JSON.parse(await detail.readBody()).instances || [];
    for (const instance of instances) {
      if (!legFinished(instance) || reportedIds.has(instance.id)) continue;
      const line = buildLegLine(instance);
      newLines.push(line);
      if (legFailed(instance)) {
        failedLegs.push(line);
      }
    }
  }

  let passed = 0;
  let failed = 0;
  let skipped = 0;
  if (done) {
    for (const run of runs) {
      passed += run.success_count || 0;
      failed += run.failure_count || 0;
      skipped += Math.max((run.total_runs || 0) - (run.success_count || 0) - (run.failure_count || 0), 0);
    }
  }

  const additions = [...newLines];
  if (done) {
    additions.push(buildSummaryLine(ref, { passed, failed, skipped }));
  }
  if (additions.length === 0) {
    console.log(`PR "${prTitle}" #${prNumber}: RC run ${ref} still executing, no new legs to report`);
    return;
  }

  await octokit.rest.issues.updateComment({
    owner,
    repo,
    comment_id: sticky.id,
    body: appendToSticky(sticky.body, additions.join('\n')),
  });
  console.log(`PR "${prTitle}" #${prNumber}: RC run ${ref}: appended ${newLines.length} leg(s), done=${done}`);

  if (done) {
    await octokit.rest.issues.createComment({
      owner,
      repo,
      issue_number: prNumber,
      body: buildCompletionCommentBody(ref, { passed, failed, skipped }, failedLegs),
    });
  }
};

export const reportAddonCompletion = async (octokit, owner, repo, pullRequest, commentId, prefix, runs) => {
  const prNumber = pullRequest.number;
  const prTitle = pullRequest.title;

  const { data: sticky } = await octokit.rest.issues.getComment({ owner, repo, comment_id: commentId });
  if (isAddonDone(sticky.body, prefix)) {
    console.log(`PR "${prTitle}" #${prNumber}: addon run ${prefix} already reported, nothing to do`);
    return;
  }

  const existingComments = await octokit.paginate(octokit.rest.issues.listComments, {
    owner,
    repo,
    issue_number: prNumber,
  });
  const marker = addonCompletionCommentMarker(prefix);
  const alreadyPosted = existingComments.some((comment) => comment.body?.includes(marker));

  if (!alreadyPosted) {
    let passed = 0;
    let failed = 0;
    let skipped = 0;
    for (const run of runs) {
      passed += run.success_count || 0;
      failed += run.failure_count || 0;
      skipped += Math.max((run.total_runs || 0) - (run.success_count || 0) - (run.failure_count || 0), 0);
    }

    await octokit.rest.issues.createComment({
      owner,
      repo,
      issue_number: prNumber,
      body: buildAddonCompletionCommentBody(prefix, { passed, failed, skipped }),
    });
  } else {
    console.log(`PR "${prTitle}" #${prNumber}: addon run ${prefix} completion comment already posted, retrying sticky marker only`);
  }

  await octokit.rest.issues.updateComment({
    owner,
    repo,
    comment_id: sticky.id,
    body: appendToSticky(sticky.body, addonDoneMarker(prefix), ADDON_STICKY_HEADER),
  });
  console.log(`PR "${prTitle}" #${prNumber}: addon run ${prefix}: reported completion`);
};

const approvePullRequest = async (octokit, owner, repo, pullRequest, reviewMessage) => {
  const prNumber = pullRequest.number;
  const prTitle = pullRequest.title;

  console.log(`PR "${prTitle}" #${prNumber}: approving`);

  try {
    const login = await getLoginForApp(octokit);
    const { data: reviews } = await octokit.rest.pulls.listReviews({ owner, repo, pull_number: prNumber });

    const prHead = pullRequest.head.sha;

    const alreadyReviewed = reviews.some(
      ({ user, commit_id, state }) =>
        user?.login === login && commit_id == prHead && state === "APPROVED"
    );
    const outstandingReviewRequest = pullRequest.requested_reviewers?.some(
      (reviewer) => reviewer.login == login
    );
    if (alreadyReviewed && !outstandingReviewRequest) {
      console.log(`PR "${prTitle}" #${prNumber}: already reviewed, nothing to do`);
      return;
    }

    console.log(`PR "${prTitle}" #${prNumber}: has not been approved yet, creating approving review`);
    await octokit.rest.pulls.createReview({
      owner: owner,
      repo: repo,
      pull_number: prNumber,
      body: reviewMessage,
      event: "APPROVE",
    });
    console.log(`PR "${prTitle}" #${prNumber}: approved`);
  } catch (error) {
    handleError(error, "Failed to approve PR");
    throw error;
  }
}

const MAYBE_READY = ["clean", "has_hooks", "unknown", "unstable"];

const mergePullRequest = async (octokit, owner, repo, pullRequest) => {
  const prNumber = pullRequest.number;
  const prTitle = pullRequest.title;

  if (pullRequest.mergeable_state == null || MAYBE_READY.includes(pullRequest.mergeable_state)) {
    console.log(`PR "${prTitle}" #${prNumber}: may be ready for merging, trying to merge`);

    try {
      await octokit.rest.pulls.merge({
        owner: owner,
        repo: repo,
        pull_number: prNumber,
      });
      console.log(`PR "${prTitle}" #${prNumber}: merged`);
    } catch (error) {
      handleError(error, "Failed to merge PR");
      throw error;
    }
  }
}

export const enablePullRequestAutomerge = async (octokit, pullRequest) => {
  const prNumber = pullRequest.number;
  const prTitle = pullRequest.title;
  const pullRequestId = pullRequest.node_id;

  const params = {
    pullRequestId: pullRequestId,
  };
  const query = `mutation ($pullRequestId: ID!) {
    enablePullRequestAutoMerge(input: {
      pullRequestId: $pullRequestId
    }) {
      pullRequest {
        autoMergeRequest {
          enabledAt
          enabledBy {
            login
          }
        }
      }
    }
  }`;
  try {
    await octokit.graphql(query, params);
    console.log(`PR "${prTitle}" #${prNumber}: auto-merge enabled`);
  } catch (error) {
    if (error instanceof GraphqlResponseError && error.errors?.some(e =>
      /pull request is in (clean|unstable) status/i.test(e.message)
    )) {
      core.error(
        'Failed to enable automerge: Make sure you have enabled branch protection with at least one status check marked as required.'
      );
    } else {
      handleError(error, 'Failed to enable automerge');
    }
    throw error;
  }
}
