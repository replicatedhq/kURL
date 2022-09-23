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
const addonRegistryUrls = {
  kotsadm: 'https://kots-kurl-addons-production-1658439274.s3.amazonaws.com/versions.json'
};

const client = new HttpClient();

const addonRegistryKurl = await client.get(`https://${bucket}.s3.amazonaws.com/external/addon-registry.json`)
  .then(response => response.readBody())
  .then(response => JSON.parse(response));

Object.keys(addonRegistryUrls).forEach(addonName => {
  info(`Scanning for addons in ${addonRegistryUrl}`)
  const addonRegistryUrl = addonRegistryUrls[addonName];
  const externalAddonRegistry = await client.get(addonRegistryUrl)
    .then(response => response.readBody())
    .then(response => JSON.parse(response));

  let hasChanges = false;
  for(const externalAddonVersion of externalAddonRegistry) {
    const addonBundleName = `${addonName}-${externalAddonVersion.version}.tar.gz`;
    const addon = addonRegistryKurl[addonBundleName];
    if(addon) {
      info(`Skipping existing addon ${addonBundleName}.`);
    } else {
      info(`Importing new addon ${addonBundleName}.`);

      info(`..Downloading addon: ${addonBundleName}`);
      try {
        await exec('curl', ['-o', addonBundleName, '-L', externalAddonVersion.url]);
      } catch (err) {
        error(err);
        continue;
      }

      info(`..Uploading addon: ${addonBundleName}`)
      try {
        await exec('aws',
          ['s3', 'cp', addonBundleName, `s3://${bucket}/external/`],
          {
            env: awsConfig
          });
      } catch (err) {
        error(err);
        continue;
      }
      if(!(addonName in addonRegistryKurl)) {
        addonRegistryKurl[addonName] = [];
      }
      addonRegistryKurl[addonName] = {
        version: externalAddonVersion.version,
        kurlVersionCompatibilityRange: externalAddonVersion.kurlVersionCompatibilityRange,
      }
      hasChanges = true;
    }
  }

  if(hasChanges) {
    try {
      await fs.writeFile('addon-registry.json', JSON.stringify(addonRegistryKurl))
      await exec('aws',
        ['s3', 'cp', 'addon-registry.json', `s3://${bucket}/external/`],
        {
          env: awsConfig,
          ignoreReturnCode: true
        });
    } catch (err) {
      error(err);
    }
  }
});
