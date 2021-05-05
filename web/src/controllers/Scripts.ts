import * as Express from "express";
import {
  Controller,
  Get,
  PathParams,
  Req,
  Res } from "ts-express-decorators";
import { instrumented } from "monkit";
import { Installer, InstallerStore } from "../installers";
import { Templates } from "../util/services/templates";
import { MetricsStore } from "../util/services/metrics";
import { logger } from "../logger";
import * as requestIP from "request-ip";

interface ErrorResponse {
  error: any;
}

const notFoundResponse = {
  error: {
    message: "The requested installer does not exist",
  },
};

@Controller("/")
export class Installers {

  constructor (
    private readonly installerStore: InstallerStore,
    private readonly templates: Templates,
    private readonly metricsStore: MetricsStore,
  ) {}

  /**
   * /<installerID>/join.sh handler
   *
   * @param response
   * @param installerID
   */
  @Get("/version/:kurlVersion/:installerID/join.sh")
  @Get("/:installerID/join.sh")
  @instrumented
  public async getJoin(
    @Res() response: Express.Response,
    @PathParams("installerID") installerID: string,
    @PathParams("kurlVersion") kurlVersion: string|void,
  ): Promise<string | ErrorResponse> {

    let installer = await this.installerStore.getInstaller(installerID);
    if (!installer) {
      response.status(404);
      return notFoundResponse;
    }
    installer = installer.resolve();

    response.set("X-Kurl-Hash", installer.hash());
    response.status(200);
    return this.templates.renderJoinScript(installer, kurlVersion);
  }

  /**
   * /<installerID>/upgrade.sh handler
   *
   * @param response
   * @param installerID
   */
  @Get("/version/:kurlVersion/:installerID/upgrade.sh")
  @Get("/:installerID/upgrade.sh")
  @instrumented
  public async getUpgrade(
    @Res() response: Express.Response,
    @PathParams("installerID") installerID: string,
    @PathParams("kurlVersion") kurlVersion: string|void,
  ): Promise<string | ErrorResponse> {

    let installer = await this.installerStore.getInstaller(installerID);
    if (!installer) {
      response.status(404);
      return notFoundResponse;
    }
    installer = installer.resolve();

    response.set("X-Kurl-Hash", installer.hash());
    response.status(200);
    return this.templates.renderUpgradeScript(installer, kurlVersion);
  }

  @Get("/version/:kurlVersion/:installerID/tasks.sh")
  @Get("/:installerID/tasks.sh")
  @instrumented
  public async getTasks(
    @Res() response: Express.Response,
    @PathParams("installerID") installerID: string,
    @PathParams("kurlVersion") kurlVersion: string|void,
  ): Promise<string | ErrorResponse> {

    let installer = await this.installerStore.getInstaller(installerID);
    if (!installer) {
      response.status(404);
      return notFoundResponse;
    }
    installer = installer.resolve();

    response.set("X-Kurl-Hash", installer.hash());
    response.status(200);
    return this.templates.renderTasksScript(installer, kurlVersion);
  }

  @Get("/")
  @Get("/version/:kurlVersion")
  public async root(
    @Res() response: Express.Response,
    @PathParams("kurlVersion") kurlVersion: string|void,
  ): Promise<string> {

    const installer = Installer.latest().resolve();

    response.set("X-Kurl-Hash", installer.hash());
    response.status(200);
    return this.templates.renderInstallScript(installer, kurlVersion);
  }

  /**
   * /<installerID> handler
   *
   * @param response
   * @param installerID
   * @returns string
   */
  @Get("/version/:kurlVersion/:installerID/install.sh")
  @Get("/:installerID/install.sh")
  @Get("/version/:kurlVersion/:installerID")
  @Get("/:installerID")
  @instrumented
  public async getInstaller(
    @Res() response: Express.Response,
    @Req() request: Express.Request,
    @PathParams("installerID") installerID: string,
    @PathParams("kurlVersion") kurlVersion: string|void,
  ): Promise<string | ErrorResponse> {

    let installer = await this.installerStore.getInstaller(installerID);
    if (!installer) {
      response.status(404);
      return notFoundResponse;
    }
    installer = installer.resolve();

    try {
      await this.metricsStore.saveSaasScriptEvent({
        installerID,
        timestamp: new Date(),
        isAirgap: false,
        clientIP: requestIP.getClientIp(request),
        userAgent: request.get("User-Agent"),
      });
    } catch (err) {
      logger.error(`Failed to save saas script event: ${err.message}`);
    }

    response.set("X-Kurl-Hash", installer.hash());
    response.status(200);
    return this.templates.renderInstallScript(installer, kurlVersion);
  }
}
