#!/usr/bin/env node

const gri = require('gaze-run-interrupt');

if (!process.env.HOST || !process.env.USER) {
  console.log("USER and HOST required");
  process.exit(1);
}

gri([
  'scripts/**/*',
  'yaml/**/*',
], [
  {
    command: 'rsync',
    args: ['-r', 'scripts', `${process.env.USER}@${process.env.HOST}:aka`],
  },{
    command: 'rsync',
    args: ['-r', 'yaml', `${process.env.USER}@${process.env.HOST}:aka`],
  }
]);
