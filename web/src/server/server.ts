import * as Sigsci from "sigsci-module-nodejs";
import {
  OverrideMiddleware,
  Req,
  Res,
  ServerLoader,
  ServerSettings,
} from "ts-express-decorators";
import * as bugsnag from "bugsnag";
import * as cors from "cors";
import { $log } from "ts-log-debug";
import * as path from "path";
import * as Express from "express";
import { ErrorMiddleware } from "./errors";
import * as RateLimit from "express-rate-limit";
import { TSEDVerboseLogging } from "../logger";
import { consoleReporter } from "replicated-lint/dist/cmdutil/reporters";

@ServerSettings({
  rootDir: path.resolve(__dirname),
  mount: {
    "/": "${rootDir}/../controllers/**/*.js",
  },
  acceptMimes: ["application/json"],
  port: 3000,
  httpsPort: 0,
  componentsScan: [
    "${rootDir}/**/**.js",
  ],
  debug: false,
  statics: {
    "/": "/dist",
    "/dist": "/dist",
  },
})

export class Server extends ServerLoader {

  constructor(
    private readonly sigsciRPCAddress: string,
    private readonly bugsnagKey: string,
  ) {
    super();
  }

  /**
   * This method let you configure the middleware required by your application to works.
   * @returns {Server}
   */
  public async $onMountingMiddlewares(): Promise<void> {
    this.expressApp.enable("trust proxy");  // so we get the real ip from the ELB in amaazon
    const bodyParser = require("body-parser");

    if (process.env["BUGSNAG_KEY"]) {
      bugsnag.register(process.env["BUGSNAG_KEY"] || "");
      this.use(bugsnag.requestHandler);
    }

    this.use(bodyParser.json());
    this.use(bodyParser.urlencoded({
      type: "application/x-www-form-urlencoded",
      extended: false,
    }));

    this.use(cors());

    if (!process.env["SIGSCI_RPC_ADDRESS"]) {
      $log.error("SIGSCI_RPC_ADDRESS not set, Signal Sciences module will not be installed");
    } else {
      const sigsci = new Sigsci({
        path: process.env.SIGSCI_RPC_ADDRESS,
      });
      this.use(sigsci.express());
    }

    if (process.env["BUGSNAG_KEY"]) {
      this.use(bugsnag.errorHandler);
    }

    if (process.env["IGNORE_RATE_LIMITS"] !== "1") {
      // this limiter applies to all requests to the service.
      let globalLimiter = new RateLimit({
        windowMs: 1000, // 1 second
        max: 10000, // limit each IP to 10000 requests per windowMs
        delayMs: 0, // disable delaying - full speed until the max limit is reached
      });
      this.use(globalLimiter);
    }
  }

  public $afterRoutesInit() {
    this.use(ErrorMiddleware);
  }

  public $onServerInitError(err) {
    $log.error(err);
  }
}

const verboseLogging = TSEDVerboseLogging;

/*
@OverrideMiddleware(LogIncomingRequestMiddleware)
export class CustomLogIncomingRequestMiddleware extends LogIncomingRequestMiddleware {

  public use(@Req() request: any, @Res() response: any) {
    // you can set a custom ID with another lib
    request.id = require("uuid").v4();
    return super.use(request, response); // required
  }

  // pretty much copy-pasted, but hooked into verboseLogging from above to control multiline logging
  protected stringify(request: Express.Request, propertySelector: (e: Express.Request) => any): (scope: any) => string {
    return (scope) => {
      if (!scope) {
        scope = {};
      }

      if (typeof scope === "string") {
        scope = {message: scope};
      }

      scope = Object.assign(scope, propertySelector(request));
      try {
        if (verboseLogging) { // this is the only line that's different
          return JSON.stringify(scope, null, 2);
        }
        return JSON.stringify(scope);
      } catch (err) {
        $log.error({error: err});
      }
      return "";
    };
  }

  protected requestToObject(request) {
    if (request.originalUrl === "/healthz" || request.url === "/healthz") {
      return {
        url: "/healthz",
      };
    }

    if (verboseLogging) {
      return {
        reqId: request.id,
        method: request.method,
        url: request.originalUrl || request.url,
        duration: new Date().getTime() - request.tsedReqStart.getTime(),
        headers: request.headers,
        body: request.body,
        query: request.query,
        params: request.params,
      };
    } else {
      return {
        reqId: request.id,
        method: request.method,
        url: request.originalUrl || request.url,
        duration: new Date().getTime() - request.tsedReqStart.getTime(),
      };
    }
  }

  protected onLogEnd(request, response) {
    if (this.requestToObject(request).url === "/healthz") {
      this.cleanRequest(request);
      return;
    }
    return super.onLogEnd(request, response);
  }
}
*/
