import * as core from '@actions/core';
import { context } from '@actions/github';
import { createAppAuth } from '@octokit/auth-app';
import { Octokit } from '@octokit/rest';
import { checkPullRequest } from './pullrequests.js';

const octokit = new Octokit({
  authStrategy: createAppAuth,
  auth: {
    appId: core.getInput('APP_ID', {required: true}),
    privateKey: core.getInput('PRIVATE_KEY', {required: true}),
    installationId: core.getInput('INSTALLATION_ID', {required: true}),
  }
});

const { owner, repo } = context.repo;

const pullRequests = await octokit.rest.pulls.list({
  owner,
  repo,
  state: 'open',
});

const pullRequestPromises = pullRequests.data.map(checkPullRequest(octokit, owner, repo));

try {
  await Promise.all(pullRequestPromises);
  console.log('All PRs checked');
} catch (error) {
  core.setFailed(error.message);
}
