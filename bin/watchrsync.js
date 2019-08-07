#!/usr/bin/env node

const gri = require('gaze-run-interrupt');

if (!process.env.HOST || !process.env.USER) {
  console.log("USER and HOST required");
  process.exit(1);
}

gri([
  'Manifest',
  'scripts/**/*',
  'yaml/**/*',
  'addons/**/*',
], [
  {
    command: 'rsync',
    args: ['Manifest', `${process.env.USER}@${process.env.HOST}:kurl`],
  },{
    command: 'rsync',
    args: ['-r', 'scripts', `${process.env.USER}@${process.env.HOST}:kurl`],
  },{
    command: 'rsync',
    args: ['-r', 'yaml', `${process.env.USER}@${process.env.HOST}:kurl`],
  },{
    command: 'rsync',
    args: ['-r', 'addons', `${process.env.USER}@${process.env.HOST}:kurl`],
  }
]);
