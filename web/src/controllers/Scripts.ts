import * as Express from "express";
import {
  Controller,
  Get,
  PathParams,
  Res } from "ts-express-decorators";
import { instrumented } from "monkit";
import { Installer, InstallerStore } from "../installers";
import { Templates } from "../util/services/templates";

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
  ) {}

  /**
   * /<installerID> handler
   *
   * @param response
   * @param installerID
   * @returns string
   */
  @Get("/:installerID")
  @Get("/:installerID/install.sh")
  @instrumented
  public async getInstaller(
    @Res() response: Express.Response,
    @PathParams("installerID") installerID: string,
  ): Promise<string | ErrorResponse> {

    let installer = await this.installerStore.getInstaller(installerID);
    if (!installer) {
      response.status(404);
      return notFoundResponse;
    }
    installer = installer.resolve();

    response.status(200);
    return this.templates.renderInstallScript(installer);
  }

  @Get("/")
  public async root(
    @Res() response: Express.Response,
  ): Promise<string> {
    const installer = Installer.latest().resolve();

    response.status(200);
    return this.templates.renderInstallScript(installer);
  }

  /**
   * /<installerID>/join.sh handler
   *
   * @param response
   * @param installerID
   */
  @Get("/:installerID/join.sh")
  @instrumented
  public async getJoin(
    @Res() response: Express.Response,
    @PathParams("installerID") installerID: string,
  ): Promise<string | ErrorResponse> {
    let installer = await this.installerStore.getInstaller(installerID);
    if (!installer) {
      response.status(404);
      return notFoundResponse;
    }
    installer = installer.resolve();

    response.status(200);
    return this.templates.renderJoinScript(installer);
  }

  /**
   * /<installerID>/upgrade.sh handler
   *
   * @param response
   * @param installerID
   */
  @Get("/:installerID/upgrade.sh")
  @instrumented
  public async getUpgrade(
    @Res() response: Express.Response,
    @PathParams("installerID") installerID: string,
  ): Promise<string | ErrorResponse> {
    let installer = await this.installerStore.getInstaller(installerID);
    if (!installer) {
      response.status(404);
      return notFoundResponse;
    }
    installer = installer.resolve();

    response.status(200);
    return this.templates.renderUpgradeScript(installer);
  }
}
