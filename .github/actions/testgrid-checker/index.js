import { getExecOutput, exec } from '@actions/exec'
import { getInput } from '@actions/core'
import { getOctokit } from '@actions/github'

const octokit = github.getOctokit(getInput('GITHUB_TOKEN'));

const pullRequests = octokit.rest.pulls.list({
  owner: 'replicatedhq',
  repo: 'kurl',
  state: 'open'
});

console.log(pullRequests);

