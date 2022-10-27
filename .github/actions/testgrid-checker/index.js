import * as core from '@actions/core'
import { getOctokit, context } from '@actions/github'
import { checkPullRequest } from './pullrequests.js'

const octokit = getOctokit(core.getInput('GITHUB_TOKEN'));
const { owner, repo } = context.repo;
const pullRequests = await octokit.rest.pulls.list({
  owner,
  repo,
  state: 'open',
});

const pullRequestPromises = pullRequests.data.map(checkPullRequest);

try {
  await Promise.all(pullRequestPromises);
  console.log('All PRs checked');
} catch (error) {
  core.setFailed(error.message);
}
