import * as semver from 'semver';
import fs from 'node:fs';
import { createHash } from 'node:crypto';

export const findVersion = (kotsAddonVersions, version) => {
  if (!kotsAddonVersions) {
    return;
  }
  console.log(kotsAddonVersions);
  return kotsAddonVersions.find(el => el.version === version.version);
};

export const appendVersion = (kotsAddonVersions, version) => {
  if (!kotsAddonVersions) {
    kotsAddonVersions = [];
  }
  kotsAddonVersions = kotsAddonVersions.filter(el => el.version !== version.version);
  kotsAddonVersions.unshift(version);
  return kotsAddonVersions.sort((a, b) => semver.compare(a.version, b.version)).reverse();
};

export const generateChecksum = async (path) => {
  return await new Promise(function (resolve, reject) {
    const hash = createHash('sha256');
    const input = fs.createReadStream(path);

    input.on('error', reject);

    input.on('data', function (chunk) {
      hash.update(chunk);
    });

    input.on('close', function () {
      resolve(hash.digest('hex'));
    });
  });
}
