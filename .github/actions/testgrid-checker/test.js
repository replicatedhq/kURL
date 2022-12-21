import * as core from '@actions/core'
import { context } from '@actions/github'
import { createAppAuth } from '@octokit/auth-app'
import { Octokit } from '@octokit/rest'
import { checkPullRequest } from './pullrequests.js'

const octokit = new Octokit({
  authStrategy: createAppAuth,
  auth: {
    appId: core.getInput('APP_ID', {required: true}),
    privateKey: core.getInput('PRIVATE_KEY', {required: true}),
    installationId: core.getInput('INSTALLATION_ID', {required: true}),
  }
});
const { owner, repo } = context.repo;

const pullRequest = await octokit.rest.pulls.get({
  owner,
  repo,
  pull_number: core.getInput('PR_NUMBER', {required: true}),
});

try {
  await checkPullRequest(octokit, owner, repo)(pullRequest.data);
} catch (error) {
  console.log(error.message);
}
