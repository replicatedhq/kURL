import * as path from "path";
import * as Express from "express";
import * as request from "request-promise";
import * as _ from "lodash";
import {
  Controller,
  Get,
  PathParams,
  Req,
  Res } from "ts-express-decorators";
import { Templates } from "../util/services/templates";
import { InstallerStore } from "../installers";
import { logger } from "../logger";
import { MetricsStore } from "../util/services/metrics";
import * as requestIP from "request-ip";

interface ErrorResponse {
  error: any;
}

const notFoundResponse = {
  error: {
    message: "The requested installer does not exist",
  },
};

interface FilepathContentsMap {
  [filepath: string]: string;
}

// Manifest for building an airgap bundle.
interface BundleManifest {
  layers: string[];
  files: FilepathContentsMap;
};

@Controller("/bundle")
export class Bundle {
  private distURL: string;
  private replicatedAppURL: string;

  constructor(
    private readonly templates: Templates,
    private readonly installers: InstallerStore,
    private readonly metricsStore: MetricsStore,
  ) {
    this.replicatedAppURL = process.env["REPLICATED_APP_URL"] || "https://replicated.app";
    this.distURL = `https://${process.env["KURL_BUCKET"]}.s3.amazonaws.com`;
    if (process.env["NODE_ENV"] === "production") {
      this.distURL += "/dist";
    } else {
      this.distURL += "/staging";
    }
  }

  /**
   * /bundle/ handler
   *
   * @param response
   * @returns {{id: any, name: string}}
   */
  @Get("/:installerID")
  public async redirect(
    @Res() response: Express.Response,
    @Req() req: Express.Request,
    @PathParams("installerID") installerID: string,
  ): Promise<BundleManifest|ErrorResponse> {

    let installer = await this.installers.getInstaller(installerID);

    if (!installer) {
      response.status(404);
      return notFoundResponse;
    }
    installer = installer.resolve();

    try {
      await this.metricsStore.saveSaasScriptEvent({
        installerID,
        timestamp: new Date(),
        isAirgap: true,
        clientIP: requestIP.getClientIp(req),
        userAgent: req.get("User-Agent"),
      });
    } catch (err) {
      logger.error(`Failed to save saas script event: ${err.message}`);
    }

    response.type("application/json");

    const ret: BundleManifest = {layers: [], files: {}};
    ret.layers = installer.packages().map((pkg) => `${this.distURL}/${pkg}.tar.gz`);

    const kotsadmApplicationSlug = _.get(installer.spec, "kotsadm.applicationSlug");
    if (kotsadmApplicationSlug) {
      try {
          logger.debug("URL:" + this.replicatedAppURL + ", SLUG:" + kotsadmApplicationSlug);
          const appMetadata = await request(`${this.replicatedAppURL}/metadata/${kotsadmApplicationSlug}`);
          const key = `addons/kotsadm/${_.get(installer.spec, "kotsadm.version")}/application.yaml`;
          ret.files[key] = appMetadata;
      } catch(err) {
          // Log the error but continue bundle execution
          // (branding metadata is optional even though user specified a app slug)
          logger.debug("Failed to fetch metadata (non-fatal error): " + err);
      }
    }

    ret.files["install.sh"] = this.templates.renderInstallScript(installer);
    ret.files["join.sh"] = this.templates.renderJoinScript(installer);
    ret.files["upgrade.sh"] = this.templates.renderUpgradeScript(installer);
    ret.files["tasks.sh"] = this.templates.renderTasksScript();

    return ret;
  }
}
