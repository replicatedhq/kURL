import { getInput } from '@actions/core'
import { getOctokit, context } from '@actions/github'
import { checkPullRequest } from './pullrequests.js'

const octokit = getOctokit(getInput('GITHUB_TOKEN', {required: true}));
const { owner, repo } = context.repo;

const pullRequest = await octokit.rest.pulls.get({
  owner,
  repo,
  pull_number: getInput('PR_NUMBER', {required: true}),
});

try {
  await checkPullRequest(pullRequest.data);
} catch (error) {
  console.log(error.message);
}
