#!/usr/bin/env node

const chokidar = require('chokidar');
const { spawn } = require('child_process');

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

let currentProcess = null;
let shouldRestart = false;
let isRunning = false;

async function runSequence() {
  isRunning = true;
  shouldRestart = false;

  for (const cmd of commands) {
    if (shouldRestart) break;

    await new Promise((resolve) => {
      currentProcess = spawn(cmd.command, cmd.args, { stdio: 'inherit' });
      currentProcess.on('close', () => {
        currentProcess = null;
        resolve();
      });
      currentProcess.on('error', () => {
        currentProcess = null;
        resolve();
      });
    });
  }

  isRunning = false;

  if (shouldRestart) {
    runSequence();
  }
}

function onChange() {
  shouldRestart = true;
  if (currentProcess) {
    currentProcess.kill();
  }
  if (!isRunning) {
    runSequence();
  }
}

chokidar.watch([
  'scripts/**/*',
  'addons/**/*',
], { ignoreInitial: true }).on('all', onChange);
