import { getInput, info, error } from '@actions/core'
import { exec } from '@actions/exec'
import { HttpClient } from '@actions/http-client';
import fs from 'node:fs/promises';

const awsConfig = {
  AWS_DEFAULT_REGION: getInput('AWS_DEFAULT_REGION', { required: true }),
  AWS_ACCESS_KEY_ID: getInput('AWS_ACCESS_KEY_ID', { required: true }),
  AWS_SECRET_ACCESS_KEY: getInput('AWS_SECRET_ACCESS_KEY', { required: true }),
};
const bucket = 'kurl-sh';
const addonRegistryUrls = [
  'https://kots-kurl-addons-production-1658439274.s3.amazonaws.com/versions.json'
];

const client = new HttpClient();

const addonRegistryKurl = await client.get(`https://${bucket}.s3.amazonaws.com/dist/external/addon-registry.json`)
  .then(response => response.readBody())
  .then(response => JSON.parse(response));

for(const addonRegistryUrl of addonRegistryUrls) {
  info(`Scanning for addons in ${addonRegistryUrl}`)
  const externalAddonRegistry = await client.get(addonRegistryUrl)
    .then(response => response.readBody())
    .then(response => JSON.parse(response));

  let hasChanges = false;
  for(const externalAddon of externalAddonRegistry) {
    const addonBundleName = `${externalAddon.addonName}-${externalAddon.addonVersion}.tar.gz`;
    const addon = addonRegistryKurl[addonBundleName];
    if(addon) {
      info(`Skipping existing addon ${addonBundleName}.`);
    } else {
      info(`Importing new addon ${addonBundleName}.`);

      info(`..Downloading addon: ${addonBundleName}`);
      try {
        await exec('curl', ['-o', addonBundleName, '-L', externalAddon.addonUrl]);
      } catch (err) {
        error(err);
        continue;
      }

      info(`..Uploading addon: ${addonBundleName}`)
      try {
        await exec('aws',
          ['s3', 'cp', addonBundleName, `s3://${bucket}/dist/external/`],
          {
            env: awsConfig
          });
      } catch (err) {
        error(err);
        continue;
      }
      addonRegistryKurl[addonBundleName] = {
        kurlVersionCompatibility: externalAddon.kurlVersionCompatibility
      }
      hasChanges = true;
    }
  }

  if(hasChanges) {
    try {
      await fs.writeFile('addon-registry.json', JSON.stringify(addonRegistryKurl))
      await exec('aws',
        ['s3', 'cp', 'addon-registry.json', `s3://${bucket}/dist/external/`],
        {
          env: awsConfig,
          ignoreReturnCode: true
        });
    } catch (err) {
      error(err);
    }
  }
}