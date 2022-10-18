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
  const thisPrComments = await octokit.rest.issues.listComments({owner, repo, issue_number: prNumber})

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
    console.log(`No testgrid run found for "${pullRequest.title}"`);
    return;
  }

  const response = await httpClient.get(`https://api.testgrid.kurl.sh/api/v1/runs?searchRef=${lastTestgridCommentPrefix}`);
  const responseBody = JSON.parse(await response.readBody());

  let passing = true;
  if(responseBody.total !== 0) {
    for (const run of responseBody.runs) {
      if (run.pending_runs > 0) {
        console.log(`PR "${pullRequest.title}" #${prNumber} has pending runs`);
        return;
      }
      if (run.failure_count > 0) {
        console.log(`PR "${pullRequest.title}" #${prNumber} has failed runs`);
        passing = false;
        break;
      }
      if (run.success_count > 0) {
        console.log(`PR "${pullRequest.title}" #${prNumber} is passing`);
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
  } else {
    console.log(`Warning: no testgrid run found for "${pullRequest.title}" #${prNumber}, despite finding comment`)
  }
});

await Promise.all(pullRequestPromises);
