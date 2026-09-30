// Run the exact checked-out generator without allowing any network upload.
const fs = require('fs');
const path = require('path');
const Module = require('module');
const assert = require('assert');
const sent = [];
const originalLoad = Module._load;
Module._load = function (id, ...args) {
  if (id === '@aws-sdk/client-s3') return {
    S3Client: class { async send(command) { sent.push(command.input); return {}; } },
    PutObjectCommand: class { constructor(input) { this.input = input; } },
  };
  return originalLoad.call(this, id, ...args);
};
process.env.S3_BUCKET = 'kurl-sh';
process.env.DIST_FOLDER = 'staging';
process.env.VERSION_TAG = 'v2026.09.20-0-825e448f5';
delete process.env.VERSIONED_ONLY;
require(path.resolve('bin/generate-addons.js'));
process.once('beforeExit', () => {
  const expected = JSON.parse(fs.readFileSync(process.argv[2])).supportedVersions;
  const actual = JSON.parse(fs.readFileSync('supported-versions-gen.json')).supportedVersions;
  assert.deepStrictEqual(actual, expected, 'Generated versions differ from preserved coherent 825e metadata');
  const keys = ['addons-gen.json', 'supported-versions-gen.json'].flatMap(name =>
    ['staging/', 'staging/v2026.09.20-0-825e448f5/'].map(prefix => prefix + name));
  assert.deepStrictEqual(sent.map(item => item.Key).sort(), keys.sort());
  assert(sent.every(item => item.Bucket === 'kurl-sh'));
  console.log('Exact-source metadata generated locally; all four attempted uploads intercepted.');
});
