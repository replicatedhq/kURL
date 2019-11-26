#!/usr/bin/env node

const gri = require('gaze-run-interrupt');

if (!process.env.REMOTES) {
  console.log("Usage: `REMOTES='user@h1.1.1.1,user@1.1.1.2' ./watchrsync.js`");
  process.exit(1);
}

const list = ['build/install.sh', 'build/join.sh', 'build/upgrade.sh', 'build/kustomize', 'build/addons', 'build/krew'];
if (process.env.SYNC_KURL_UTIL_IMAGE) {
  list.push('build/shared');
}

const commands = [
  {
    command: 'rm',
    args: ['-rf'].concat(list),
  },{
    command: 'make',
    args: list,
  }
];

process.env.REMOTES.split(",").forEach(function(remote) {
  commands.push({
    command: 'rsync',
    args: ['-r', 'build/', `${remote}:kurl`],
  });
});

commands.push({
  command: "echo",
  args: ["synced"],
});

gri([
  'scripts/**/*',
  'addons/**/*',
], commands);
