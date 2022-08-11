import * as sourceMapSupport from "source-map-support";
import * as util from "util";
import {$log} from "@tsed/common";
import {PlatformExpress} from "@tsed/platform-express";
import Bugsnag from "@bugsnag/js";
import BugsnagPluginExpress from "@bugsnag/plugin-express";
import { initMysqlPool } from "../util/persistence/mysql";
import { Server } from "../server/server";
import * as metrics from "../metrics";
import {startExternalAddonPulling} from "../installers/installer-versions"

exports.name = "serve";
exports.describe = "Run the server";
exports.builder = {
  bugsnagKey: {
    type: "string",
    demand: false,
  },
};

exports.handler = (argv: any) => {
  main(argv).catch((err) => {
    console.log(`Failed with error ${util.inspect(err)}`);
    process.exit(1);
  });
};

export async function main(argv: any): Promise<void> {
  sourceMapSupport.install();

  if (process.env["NEW_RELIC_LICENSE_KEY"]) {
    require("newrelic");
  }

  if (process.env["BUGSNAG_KEY"]) {
    Bugsnag.start({
      apiKey: process.env["BUGSNAG_KEY"] || "",
      releaseStage: process.env["NODE_ENV"],
      plugins: [BugsnagPluginExpress],
      appVersion: process.env["VERSION"],
    });
  }
  await startExternalAddonPulling();

  metrics.bootstrapFromEnv();

  await initMysqlPool();

  try {
    $log.debug("Start server...");
    const platform = await PlatformExpress.bootstrap(Server, {
      // extra settings
    });

    process.on('SIGTERM', async () => {
      console.log("SIGTERM received");
      await platform.stop();
      process.exit(0);
    })

    await platform.listen();
    $log.debug("Server initialized");
  } catch (er) {
    $log.error(er);
  }
}
