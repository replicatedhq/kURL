import * as core from '@actions/core';
import { getOctokit, context } from '@actions/github'
import { HttpClient } from '@actions/http-client'
import { enablePullRequestAutomerge } from './github.js'
import { RequestError } from "@octokit/request-error";

const octokit = getOctokit(core.getInput('GITHUB_TOKEN'));
const { owner, repo } = context.repo

const httpClient = new HttpClient();

export const checkPullRequest = async pullRequest => {
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
            await approvePullRequest(pullRequest, "Automation (testgrid-checker): passing"),
            await enablePullRequestAutomerge(pullRequest.node_id),
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

const approvePullRequest = async (pullRequest, reviewMessage) => {
  const prNumber = pullRequest.number;
  const prTitle = pullRequest.title;

  console.log(`PR "${prTitle}" #${prNumber}: approving`);

  try {
    const [login, { data: reviews }] = await Promise.all([
      getLoginForToken(octokit),
      octokit.rest.pulls.listReviews({ owner, repo, pull_number: prNumber }),
    ]);

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
    if (error instanceof RequestError) {
      switch (error.status) {
        case 401:
          core.error(
            `${error.message}. Please check that the \`github-token\` input ` +
              "parameter is set correctly."
          );
          break;
        case 403:
          core.error(
            `${error.message}. In some cases, the GitHub token used for actions triggered ` +
              "from `pull_request` events are read-only, which can cause this problem. " +
              "Switching to the `pull_request_target` event typically resolves this issue."
          );
          break;
        case 404:
          core.error(
            `${error.message}. This typically means the token you're using doesn't have ` +
              "access to this repository. Use the built-in `${{ secrets.GITHUB_TOKEN }}` token " +
              "or review the scopes assigned to your personal access token."
          );
          break;
        case 422:
          core.error(
            `${error.message}. This typically happens when you try to approve the pull ` +
              "request with the same user account that created the pull request. Try using " +
              "the built-in `${{ secrets.GITHUB_TOKEN }}` token, or if you're using a personal " +
              "access token, use one that belongs to a dedicated bot account."
          );
          break;
        default:
          core.error(`Error (code ${error.status}): ${error.message}`);
      }
    } else if (error instanceof Error) {
      core.error(error);
    } else {
      core.error("Unknown error");
    }
    throw error;
  }
}

async function getLoginForToken() {
  try {
    const { data: user } = await octokit.rest.users.getAuthenticated();
    return user.login;
  } catch (error) {
    if (error instanceof RequestError) {
      // If you use the GITHUB_TOKEN provided by GitHub Actions to fetch the current user
      // you get a 403. For now we'll assume any 403 means this is an Actions token.
      if (error.status === 403) {
        return "github-actions[bot]";
      }
    }
    throw error;
  }
}
