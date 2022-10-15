import { getInput } from '@actions/core'
import { getOctokit, context } from '@actions/github'
import { HttpClient } from '@actions/http-client'

const octokit = getOctokit(getInput('GITHUB_TOKEN'));
const {owner, repo} = context.repo
const pullRequests = await octokit.rest.pulls.list({
  owner,
  repo,
  state: 'open'
});

const httpClient = new HttpClient();

const pullRequestPromises = pullRequests.data.map(async pullRequest => {
  const prNumber = pullRequest.number;
  const prHeadSha = pullRequest.merge_commit_sha.slice(0,7);
  const response = await httpClient.get(`https://api.testgrid.kurl.sh/api/v1/runs?searchRef=pr-${prNumber}-${prHeadSha}`);
  const responseBody = JSON.parse(await response.readBody());

  let passing = true;
  if(responseBody.total !== 0) {
    for (const run of responseBody.runs) {
      if (run.pending_runs > 0) {
        console.log(`PR "${pullRequest.title}" #${prNumber} commit ${prHeadSha} has pending runs`);
        return;
      }
      if (run.failure_count > 0) {
        console.log(`PR "${pullRequest.title}" #${prNumber} commit ${prHeadSha} has failed runs`);
        passing = false;
        break;
      }
      if (run.success_count > 0) {
        console.log(`PR "${pullRequest.title}" #${prNumber} commit ${prHeadSha} is passing`);
        break;
      }
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
});

await Promise.all(pullRequestPromises);
