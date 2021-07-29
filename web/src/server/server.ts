import {Configuration, PlatformApplication} from "@tsed/common";
import {Inject} from "@tsed/di";
import * as bugsnag from "bugsnag";
import * as cors from "cors";
import * as path from "path";
import * as RateLimit from "express-rate-limit";
import * as express from "express";
import { ErrorMiddleware } from "./errors";

@Configuration({
  rootDir: path.resolve(__dirname),
  mount: {
    "/": "${rootDir}/../controllers/**/*.ts",
  },
  acceptMimes: ["application/json", "application/yaml", "text/yaml"],
  port: 3000,
  httpsPort: 0,
  componentsScan: [
    "${rootDir}/../util/services/**/*.ts",
    "${rootDir}/../installers/**/*.ts",
    "${rootDir}/**/*.ts",
  ],
  logger: {
    level: process.env["NODE_ENV"] === "development" ? "debug" : "info",
    ignoreUrlPatterns: ["healthz"],
  },
})

export class Server {
  @Inject()
  app: PlatformApplication<express.Application>;

  $beforeRoutesInit(): void | Promise<any> {
    this.app.getApp().enable("trust proxy"); // so we get the real ip from the ELB in amaazon

    // eslint-disable-next-line @typescript-eslint/no-var-requires
    if (process.env["BUGSNAG_KEY"]) {
      bugsnag.register(process.env["BUGSNAG_KEY"] || "", {
        releaseStage: process.env["NODE_ENV"],
      });
      this.app.use(bugsnag.requestHandler);
    }

    this.app.use(express.json());
    this.app.use(express.urlencoded({
      type: "application/x-www-form-urlencoded",
      extended: false,
    }));
    this.app.use(express.text({
      type: ["text/plain", "text/yaml", "text/x-yaml", "application/x-yaml"],
    }));

    this.app.use(cors());

    if (process.env["BUGSNAG_KEY"]) {
      this.app.use(bugsnag.errorHandler);
    }

    if (process.env["IGNORE_RATE_LIMITS"] !== "1") {
      // this limiter applies to all requests to the service.
      const globalLimiter = new RateLimit({
        windowMs: 1000, // 1 second
        max: 10000, // limit each IP to 10000 requests per windowMs
        delayMs: 0, // disable delaying - full speed until the max limit is reached
      });
      this.app.use(globalLimiter);
    }
  }

  $afterRoutesInit(): void | Promise<any> {
    this.app.use(ErrorMiddleware);
  }
}
