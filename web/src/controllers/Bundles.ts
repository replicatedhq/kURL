
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
import { getDistUrl, getPackageUrl } from "../util/package";

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
}

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
    this.distURL = getDistUrl();
  }

  /**
   * /bundle/ handler
   *
   * @param response
   * @returns {{id: any, name: string}}
   */
  @Get("/:installerID")
  @Get("/version/:kurlVersion/:installerID")
  public async redirect(
    @Res() response: Express.Response,
    @Req() req: Express.Request,
    @PathParams("installerID") installerID: string,
    @PathParams("kurlVersion") kurlVersion: string|undefined,
  ): Promise<BundleManifest|ErrorResponse> {

    let installer = await this.installers.getInstaller(installerID);

    if (!installer) {
      response.status(404);
      return notFoundResponse;
    }
    installer = await installer.resolve();

    // if installer.spec.kurl is set, fallback to installer.spec.kurl.installerVersion if kurlVersion was not set in the URL
    kurlVersion = installer.spec.kurl ? (kurlVersion || installer.spec.kurl.installerVersion) : kurlVersion;

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
    ret.layers = (await installer.packages(kurlVersion)).map((pkg) => getPackageUrl(this.distURL, kurlVersion, `${pkg}.tar.gz`));

    const kotsadmApplicationSlug = _.get(installer.spec, "kotsadm.applicationSlug");
    if (kotsadmApplicationSlug) {
      try {
          logger.debug("URL:" + this.replicatedAppURL + ", SLUG:" + kotsadmApplicationSlug);
          const appMetadata = await request(`${this.replicatedAppURL}/metadata/${kotsadmApplicationSlug}`);
          const key = `kurl/addons/kotsadm/${_.get(installer.spec, "kotsadm.version")}/application.yaml`;
          ret.files[key] = appMetadata;
      } catch (err) {
          // Log the error but continue bundle execution
          // (branding metadata is optional even though user specified a app slug)
          logger.debug("Failed to fetch metadata (non-fatal error): " + err);
      }
    }

    ret.files["install.sh"] = await this.templates.renderInstallScript(installer, kurlVersion);
    ret.files["join.sh"] = await this.templates.renderJoinScript(installer, kurlVersion);
    ret.files["upgrade.sh"] = await this.templates.renderUpgradeScript(installer, kurlVersion);
    ret.files["tasks.sh"] = await this.templates.renderTasksScript(installer, kurlVersion);

    return ret;
  }
}
