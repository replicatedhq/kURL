import { GraphqlResponseError } from '@octokit/graphql';
import * as core from '@actions/core';
import { getOctokit } from '@actions/github'

export const enablePullRequestAutomerge = async (pullRequestId) => {
  const octokit = getOctokit(core.getInput('AUTOMERGE_GITHUB_TOKEN') || core.getInput('GITHUB_TOKEN'));

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
    const response =
      await octokit.graphql(
        query,
        params
      );
    return response.enablePullRequestAutoMerge.pullRequest.autoMergeRequest;
  } catch (error) {
    if (error instanceof GraphqlResponseError) {
      if (
        error.errors?.some(e =>
          /pull request is in (clean|unstable) status/i.test(e.message)
        )
      ) {
        core.error(
          'ERROR: Unable to enable automerge. Make sure you have enabled branch protection with at least one status check marked as required.'
        );
      }
    }
    throw error;
  }
};
