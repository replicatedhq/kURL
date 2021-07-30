import * as util from "util";
import {$log} from "@tsed/common";
import {PlatformExpress} from "@tsed/platform-express";
import { initMysqlPool } from "../util/persistence/mysql";
import { Server } from "../server/server";
import * as metrics from "../metrics";

exports.name = "serve";
exports.describe = "Run the server";
exports.builder = {
  bugsnagKey: {
    type: "string",
    demand: false,
  },
};

exports.handler = (argv) => {
  main(argv).catch((err) => {
    console.log(`Failed with error ${util.inspect(err)}`);
    process.exit(1);
  });
};

export async function main(argv: any): Promise<void> {
  if (process.env["NEW_RELIC_LICENSE_KEY"]) {
    require("newrelic");
  }

  metrics.bootstrapFromEnv();

  await initMysqlPool();

  try {
    $log.debug("Start server...");
    const platform = await PlatformExpress.bootstrap(Server, {
      // extra settings
    });

    await platform.listen();
    $log.debug("Server initialized");
  } catch (er) {
    $log.error(er);
  }
}
