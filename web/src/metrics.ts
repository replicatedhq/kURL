import * as StatsdClient from "statsd-client";
import fetch from "node-fetch";

import {
  getRegistry,
  StatsdReporter,
  StatusPageReporter,
} from "monkit";
import {logger} from "./logger";

export function startStatsdReporter(
  statsdHost: string,
  statsdPort: number,
  intervalMs: number,
  prefix: string,
): void {
  logger.info(`starting statsd reporter ${statsdHost}:${statsdPort} at interval ${intervalMs}ms`);
  const reporter = new StatsdReporter(
    getRegistry(),
    prefix,
    new StatsdClient({host: statsdHost, port: statsdPort}),
  );
  logger.info("created");

  setInterval(() => {
    reporter.report();
  }, intervalMs);
  logger.info("started");
}

export function startStatusPageReporter(
  url: string,
  pageId: string,
  statusPageToken: string,
  metricIds: any,
  intervalMs: number,
): void {
  logger.info(`starting statusPage reporter ${url}/${pageId} at interval ${intervalMs}ms`);

  const reporter = new StatusPageReporter(
    getRegistry(),
    url,
    pageId,
    statusPageToken,
    metricIds,
  );
  logger.info("created");

  setInterval(() => {
    reporter.report();
  }, intervalMs);
  logger.info("started");
}

export async function bootstrapFromEnv(): Promise<void> {
  let statsdIpAddress;

  if (process.env["USE_EC2_PARAMETERS"]) {
    const res = await fetch("http://169.254.169.254/latest/meta-data/local-ipv4");
    statsdIpAddress = await res.text();
  }

  const statsdHost = statsdIpAddress || process.env.STATSD_IP_ADDRESS;
  const statsdPort = Number(process.env.STATSD_PORT) || 8125;
  const statsdIntervalMillis = Number(process.env.STATSD_INTERVAL_MILLIS) || 30000;
  const statsdPrefix = process.env.STATSD_PREFIX || "";

  if (!statsdHost) {
    logger.error("neither the AWS Metadata Service nor STATSD_HOST is set, metrics will not be reported to statsd");
  } else {
    startStatsdReporter(statsdHost, statsdPort, statsdIntervalMillis, statsdPrefix);
  }

  const statusPageToken = process.env.STATUSPAGEIO_TOKEN;
  const statusPagePageId = process.env.STATUSPAGEIO_PAGE_ID || ""; // Replicated Production
  const statusPageUrl = process.env.STATUSPAGEIO_URL || "api.statuspage.io";
  const intervalMs = Number(process.env.STATUSPAGEIO_INTERVAL_MILLIS) || 30000;
  const metricIds = {
  };

  if (!(statusPageToken)) {
    logger.error("STATUSPAGEIO_TOKEN not set, metrics will not be reported to statuspage.io");
    return;
  }

  startStatusPageReporter(
    statusPageUrl,
    statusPagePageId,
    statusPageToken,
    metricIds,
    intervalMs,
  );

}
