import * as core from '@actions/core';
import { RequestError } from '@octokit/request-error';

export const getLoginForApp = async (octokit) => {
  const { data: app } = await octokit.rest.apps.getAuthenticated();
  return `${app.slug}[bot]`;
}

export const handleError = (error, prefix) => {
  if (error instanceof RequestError) {
    core.error(`${prefix}: Error (code ${error.status}): ${error.message}`);
  } else if (error instanceof Error) {
    core.error(`${prefix}: ${error}`);
  } else {
    core.error(`${prefix}: Unknown error`);
  }
}
