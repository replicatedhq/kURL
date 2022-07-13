import { DestinationStream, LoggerOptions, pino } from "pino";
import pretty from "pino-pretty";
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
  const options: LoggerOptions = {
    name: component,
    level: pinoLevel,
  };

  let stream: DestinationStream = dest;
  if (process.env.PINO_LOG_PRETTY) {
    stream = pretty({
      destination: dest,
    })
  }

  return pino(options, stream).child({
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
