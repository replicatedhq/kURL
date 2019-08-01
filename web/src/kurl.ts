#!/usr/bin/env node

import * as yargs from "yargs";

yargs
  .commandDir("../build/commands")
  .env()
  .help()
  .demandCommand()
  .argv;
