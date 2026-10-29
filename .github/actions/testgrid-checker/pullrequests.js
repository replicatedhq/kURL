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
} from './rcrun.js';

const httpClient = new HttpClient();
const TESTGRID_API = 'https://api.testgrid.kurl.sh/api/v1';

export const checkPullRequest = (octokit, owner, repo) => async pullRequest => {
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

  // The run entry to watch is the LATEST in document order: either a
  // standalone comment (legacy test-addon flow) or a line inside the single
  // sticky comment the testgrid-pr workflow appends to. Same "last wins"
  // semantics the addon flow always had, now across both sources.
  const lastEntry = findLastRunEntry(thisPrComments);
  if (!lastEntry) {
    console.log(`PR "${prTitle}" #${prNumber}: no testgrid run found`);
    return;
  }

  if (isRCRef(lastEntry.ref)) {
    await checkRCRun(octokit, owner, repo, pullRequest, lastEntry);
    return;
  }

  const lastTestgridCommentPrefix = addonRefPrefix(lastEntry.ref) || lastEntry.ref;

  const response = await httpClient.get(`https://api.testgrid.kurl.sh/api/v1/runs?searchRef=${lastTestgridCommentPrefix}`);
  const responseBody = JSON.parse(await response.readBody());

  let passing = true;
  if (responseBody.total !== 0) {
    for (const run of responseBody.runs) {
      if (run.pending_runs > 0) {
        console.log(`PR "${prTitle}" #${prNumber}: has pending runs`);
        return;
      }
      if (run.running_runs > 0) {
        console.log(`PR "${pullRequest.title}" #${prNumber} has running runs`);
        return;
      }
      if (run.failure_count > 0) {
        console.log(`PR "${prTitle}" #${prNumber}: has failed runs`);
        passing = false;
        break;
      }
      if (run.success_count > 0) {
        console.log(`PR "${prTitle}" #${prNumber}: is passing`);
        break;
      }
    }
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
const checkRCRun = async (octokit, owner, repo, pullRequest, entry) => {
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

  const response = await httpClient.get(`${TESTGRID_API}/runs?searchRef=${encodeURIComponent(rcSearchRef(ref))}`);
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
    const detail = await httpClient.post(`${TESTGRID_API}/run/${encodeURIComponent(run.id)}`, '{}');
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
