#!/usr/bin/env node

const gri = require('gaze-run-interrupt');

if (!process.env.REMOTES) {
  console.log("Usage: `REMOTES='user@h1.1.1.1,user@1.1.1.2' ./watchrsync.js`");
  process.exit(1);
}

const list = ['build/install.sh', 'build/join.sh', 'build/upgrade.sh', 'build/tasks.sh', 'build/kustomize', 'build/manifests', 'build/addons']
if (!process.env.NO_BIN) {
  list.push('build/krew', 'build/kurlkinds', 'build/helm', 'build/bin');
}
if (process.env.SYNC_KURL_UTIL_IMAGE) {
  list.push('build/shared');
}

const commands = [
  {
    command: 'rm',
    args: ['-rf'].concat(list),
  },{
    command: 'make',
    args: list.concat('DEV=1'),
  }
];

process.env.REMOTES.split(",").forEach(function(remote) {
  commands.push({
    command: 'rsync',
    args: ['-r', 'build/install.sh', 'build/join.sh', 'build/upgrade.sh', 'build/tasks.sh', `${remote}:`],
  });
  commands.push({
    command: 'rsync',
    args: ['-r', 'build/', `${remote}:kurl`],
  });
});

commands.push({
  command: "date",
  args: [],
});

commands.push({
  command: "echo",
  args: ["synced"],
});

gri([
  'scripts/**/*',
  'addons/**/*',
], commands);
