import * as pino from "pino";
import * as stream from "stream";
import * as fs from "fs";

export const TSEDVerboseLogging =
  process.env["NODE_ENV"] !== "production" &&
  process.env["NODE_ENV"] !== "staging" &&
  !process.env.TSED_SUPPRESS_ACCESSLOG;

export const pinoLevel = process.env.PINO_LOG_LEVEL || "info";

function initLoggerFromEnv(): pino.Logger {

  const dest = process.env.LOG_FILE ?
    fs.createWriteStream(process.env.LOG_FILE) :
    process.stdout;

  const component = "kurl";
  const options = {
    name: component,
    level: pinoLevel,
    prettyPrint: !!process.env.PINO_LOG_PRETTY,
  };

  return pino(options, dest).child({
    version: process.env.VERSION,
    component,
  });
}

export const logger = initLoggerFromEnv();

export function log(...msg: any[]): void {
  if (msg.length >= 0) {
    const arg = msg[0];
    msg.splice(0, 1);
    logger.info(arg, ...msg);
  }
}
