import * as path from "path";
import * as Express from "express";
import * as tar from "tar-stream";
import {
  Controller,
  Get,
  PathParams,
  Res } from "ts-express-decorators";
import { Templates } from "../util/services/templates";
import { InstallerStore } from "../installers";

interface ErrorResponse {
  error: any;
}

const notFoundResponse = {
  error: {
    message: "The requested installer does not exist",
  },
};

@Controller("/bundle")
export class Bundle {
  private distOrigin: string;

  constructor(
    private readonly templates: Templates,
    private readonly installers: InstallerStore,
  ) {
    this.distOrigin = `https://${process.env["KURL_BUCKET"]}.s3.amazonaws.com`;
  }

  /**
   * /bundle/ handler
   *
   * @param response
   * @returns {{id: any, name: string}}
   */
  @Get("/:pkg")
  public async redirect(
    @Res() response: Express.Response,
    @PathParams("pkg") pkg: string,
  ): Promise<void|ErrorResponse> {

    const installerID = path.basename(pkg, ".tar.gz");
    // TODO remove
    console.log(`Looking up installer ${installerID}`);

    const installer = await this.installers.getInstaller(installerID);

    if (!installer) {
      response.status(404);
      return notFoundResponse;
    }

    const pack = tar.pack();

    pack.pipe(response);

    pack.entry({ name: "install.sh" }, this.templates.renderInstallScript(installer));
    pack.entry({ name: "join.sh" }, this.templates.renderJoinScript(installer));
    pack.entry({ name: "upgrade.sh" }, this.templates.renderUpgradeScript(installer));

    pack.finalize();
  }
}
