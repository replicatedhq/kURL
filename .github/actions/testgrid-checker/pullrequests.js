import * as core from '@actions/core';
import { HttpClient } from '@actions/http-client';
import { GraphqlResponseError } from '@octokit/graphql';
import { handleError } from './github.js';

const httpClient = new HttpClient();

export const checkPullRequest = (octokit, owner, repo) => async pullRequest => {
  const prNumber = pullRequest.number;
  const prTitle = pullRequest.title;
  console.log(`PR "${prTitle}" #${prNumber}: checking`);

  const thisPrComments = await octokit.rest.issues.listComments({ owner, repo, issue_number: prNumber });

  let lastTestgridCommentID = 0;
  let lastTestgridCommentPrefix = "";
  for (const comment of thisPrComments.data) {
    if (comment.id > lastTestgridCommentID) {
      // matches comments like "Testgrid Run(s) Executing @ https://testgrid.kurl.sh/run/pr-3569-3eb59f9-rook-1.9.12-k8s-docker-2022-10-12T23:30:47Z"
      const matches = comment.body.match('Testgrid Run\\(s\\) Executing @\\W+https:\\/\\/testgrid.kurl.sh\\/run\\/(pr-\\d+-\\w+)')
      if (matches) {
        lastTestgridCommentID = comment.id;
        lastTestgridCommentPrefix = matches[1];
      }
    }
  }

  if (lastTestgridCommentID === 0) {
    console.log(`PR "${prTitle}" #${prNumber}: no testgrid run found`);
    return;
  }

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
          await Promise.all([
            approvePullRequest(octokit, owner, repo, pullRequest, "Automation (testgrid-checker): passing"),
            enablePullRequestAutomerge(octokit, pullRequest),
            mergePullRequest(octokit, owner, repo, pullRequest),
          ]);
        } catch (error) {
          // nothing to do as we already logged the error
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
        owner,
        repo,
        prNumber,
      });
    } catch (error) {
      handleError(error, "Failed to merge PR");
      throw error;
    }
  }
}

export const enablePullRequestAutomerge = async (octokit, pullRequest) => {
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
    const response = await octokit.graphql(query, params);
    return response.enablePullRequestAutoMerge.pullRequest.autoMergeRequest;
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
