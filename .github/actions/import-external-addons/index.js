import { getInput, info, setFailed } from '@actions/core'
import { exec } from '@actions/exec'
import { HttpClient } from '@actions/http-client';
import fs from 'node:fs/promises';
import { appendVersion, findVersion, generateChecksum, isVersionReleasing } from './util.js';

const main = async () => {
  const debug = process.env.DEBUG;

  let awsConfig = {};
  if(!debug) {
    awsConfig = {
      AWS_DEFAULT_REGION: getInput('AWS_DEFAULT_REGION', { required: true }),
      AWS_ACCESS_KEY_ID: getInput('AWS_ACCESS_KEY_ID', { required: true }),
      AWS_SECRET_ACCESS_KEY: getInput('AWS_SECRET_ACCESS_KEY', { required: true }),
    };
  }
  const bucket = 'kurl-sh';
  const addonRegistryUrls = {
    kotsadm: 'https://kots-kurl-addons-production-1658439274.s3.amazonaws.com/versions.json'
  };

  const client = new HttpClient();

  let addonRegistryKurl = {};
  const res = await client.get(`https://${bucket}.s3.amazonaws.com/external/addon-registry.json`);
  if(res.message.statusCode === 200) {
    addonRegistryKurl = JSON.parse(await res.readBody());
    if(Array.isArray(addonRegistryKurl)) {
      addonRegistryKurl = {};
    }
  }

  Object.keys(addonRegistryUrls).forEach(async addonName => {
    const addonRegistryUrl = addonRegistryUrls[addonName];
    info(`Scanning for addons in ${addonRegistryUrl}`)
    const externalAddonRegistry = await client.get(addonRegistryUrl)
      .then(response => response.readBody())
      .then(response => JSON.parse(response));

    let hasChanges = false;
    for(const externalAddonVersion of externalAddonRegistry) {
      const addonBundleName = `${addonName}-${externalAddonVersion.version}.tar.gz`;
      const next = {
        version: externalAddonVersion.version,
        kurlVersionCompatibilityRange: externalAddonVersion.kurlVersionCompatibilityRange,
        origin: externalAddonVersion.url,
        isPrerelease: externalAddonVersion.isPrerelease || false,
      };
      const existing = findVersion(addonRegistryKurl[addonName], next);
      if(existing) {
        if (isVersionReleasing(existing, next)) {
          info(`Releasing addon ${addonBundleName}.`);
  
          // only allow changing isPrerelease property for now
          existing.isPrerelease = false;
          addonRegistryKurl[addonName] = appendVersion(addonRegistryKurl[addonName], existing);
          hasChanges = true;
        } else {
          // At the moment we treat the version as immutable.
          // In the future we could check the hash and overwrite.
          info(`Skipping existing addon ${addonBundleName}.`);
        }
      } else {
        info(`Importing new addon ${addonBundleName}.`);

        info(`..Downloading addon: ${addonBundleName}`);
        await exec('curl', ['-o', addonBundleName, '-L', externalAddonVersion.url]);

        next.sha256Sum = await generateChecksum(addonBundleName);

        info(`..Uploading addon: ${addonBundleName}`);
        if(!debug) {
          await exec('aws',
            ['s3', 'cp', addonBundleName, `s3://${bucket}/external/`],
            {
              env: awsConfig
            });
        }
        addonRegistryKurl[addonName] = appendVersion(addonRegistryKurl[addonName], next);
        hasChanges = true;
      }
    }

    if(hasChanges) {
      if(debug) {
        console.log('OUT = ' + JSON.stringify(addonRegistryKurl));
      } else {
        await fs.writeFile('addon-registry.json', JSON.stringify(addonRegistryKurl))
        await exec('aws',
          ['s3', 'cp', 'addon-registry.json', `s3://${bucket}/external/`],
          {
            env: awsConfig,
            ignoreReturnCode: true
          });
      }
    }
  });
}

(async function (){
  try {
    await main();
  } catch (error) {
    setFailed(error.message);
  }
})();
