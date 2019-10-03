import * as path from "path";
import * as zlib from "zlib";
import * as Express from "express";
import * as tar from "tar-stream";
import * as request from "request";
import * as gunzip from "gunzip-maybe";
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
    const installer = await this.installers.getInstaller(installerID);

    if (!installer) {
      response.status(404);
      return notFoundResponse;
    }

    const pack = tar.pack();

    response.type("application/gzip");
    response.set("Content-Encoding", "gzip");

    pack.pipe(zlib.createGzip()).pipe(response);

    const packages = installer.packages().map((pkg) => `${this.distOrigin}/dist/${pkg}.tar.gz`);

    for (let i = 0; i < packages.length; i++) {
      await copy(packages[i], pack);
    }

    pack.entry({ name: "join.sh" }, this.templates.renderJoinScript(installer));
    pack.entry({ name: "upgrade.sh" }, this.templates.renderUpgradeScript(installer));
    // send last to protect against interrupted downloads
    pack.entry({ name: "install.sh" }, this.templates.renderInstallScript(installer));

    pack.finalize();

    await new Promise((resolve, reject) => {
      pack.on("end", resolve);
      pack.on("error", reject);
    });
  }
}

const copy = async(url: string, dst: any) => {
  return new Promise((resolve, reject) => {
    const extract = tar.extract();

    request(url).pipe(gunzip()).pipe(extract);

    extract.on("entry", (header, stream, done) => {
      stream.pipe(dst.entry(header, done));
    });

    extract.on("finish", resolve);
    extract.on("error", reject);
  });
};
