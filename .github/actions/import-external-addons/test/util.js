import { expect } from 'chai';
import { it } from 'mocha';
import os from 'os';
import fs from 'node:fs/promises';
import { appendVersion, findVersion, generateChecksum, isVersionReleasing } from '../util.js';

describe ('findVersion', () => {
  it('finds version', () => {
    const version = findVersion([{version: '1.84.0'}, {version: '1.85.0'}], {version: '1.85.0'});
    expect(version).to.deep.equal({version: '1.85.0'});
  });

  it('doesn\'t find version', () => {
    const version = findVersion([{version: '1.84.0'}, {version: '1.85.0'}], {version: '1.84.1'});
    expect(version).to.be.undefined;
  });
});

describe ('appendVersion', () => {
  it('appends a new version', () => {
    const versions = appendVersion([{version: '1.84.0'}, {version: '1.85.0'}], {version: '1.84.1'});
    expect(versions).to.deep.equal([{version: '1.85.0'}, {version: '1.84.1'}, {version: '1.84.0'}]);
  });

  it('de-dupes duplicate versions', () => {
    const versions = appendVersion([{version: '1.84.0'}, {version: '1.85.0'}], {version: '1.85.0'});
    expect(versions).to.deep.equal([{version: '1.85.0'}, {version: '1.84.0'}]);
  });

  it('works for first version', () => {
    const versions = appendVersion(undefined, {version: '1.85.0'});
    expect(versions).to.deep.equal([{version: '1.85.0'}]);
  });
});

describe ('generateChecksum', () => {
  it('generates consistent checksum', async () => {
    const filename = `${os.tmpdir()}/file1-${Math.floor(Date.now() / 1000)}`;
    await fs.writeFile(filename, "CONTENTS");
    const checksum1 = await generateChecksum(filename);
    expect(checksum1).to.have.length(64);
    const checksum2 = await generateChecksum(filename);
    expect(checksum1).to.equal(checksum2);
  });
});

describe ('isVersionReleasing', () => {
  it('is not releasing', () => {
    const isReleasing = isVersionReleasing({isPrerelease: false}, {isPrerelease: false});
    expect(isReleasing).to.be.false;
  });

  it('is releasing', () => {
    const isReleasing = isVersionReleasing({isPrerelease: true}, {isPrerelease: false});
    expect(isReleasing).to.be.true;
  });

  it('undefined', () => {
    const isReleasing = isVersionReleasing({}, {isPrerelease: false});
    expect(isReleasing).to.be.false;
  });

  it('null', () => {
    const isReleasing = isVersionReleasing(null, {isPrerelease: false});
    expect(isReleasing).to.be.false;
  });
});
