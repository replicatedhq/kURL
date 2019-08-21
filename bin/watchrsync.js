#!/usr/bin/env node

const gri = require('gaze-run-interrupt');

if (!process.env.HOST || !process.env.USER) {
  console.log("USER and HOST required");
  process.exit(1);
}

gri([
  'scripts/**/*',
  'addons/**/*',
], [
  {
    command: 'rm',
    args: ['-rf', 'build/install.sh', 'build/join.sh', 'build/yaml', 'build/addons'],
  },{
    command: 'make',
    args: ['build/install.sh', 'build/join.sh', 'build/yaml', 'build/addons'],
  },{
    command: 'rsync',
    args: ['-r', 'build/', `${process.env.USER}@${process.env.HOST}:kurl`],
  }
]);
