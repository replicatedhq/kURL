import { getExecOutput, exec } from '@actions/exec'
import { getInput } from '@actions/core'
import { getOctokit } from '@actions/github'

const octokit = getOctokit(getInput('GITHUB_TOKEN'));

const pullRequests = await octokit.rest.pulls.list({
  owner: 'replicatedhq',
  repo: 'kurl',
  state: 'open'
});

console.log(pullRequests);

