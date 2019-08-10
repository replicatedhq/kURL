import * as Express from "express";
import * as fs from "fs";
import * as path from "path";
import * as _ from "lodash";
import {
  Controller,
  Get,
  PathParams,
  Post,
  Req,
  Res } from "ts-express-decorators";
import { instrumented } from "monkit";
import { Installer, InstallerStore } from "../installers";

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

  private kurlURL: string;
  private installTmpl: (any) => string;
  private joinTmpl: (any) => string;

  constructor (
    private readonly installerStore: InstallerStore,
  ) {
    this.kurlURL = process.env["KURL_URL"] || "https://kurl.sh";

    const tmplDir = path.join(__dirname, "../../../templates");
    const installTmplPath = path.join(tmplDir, "install.tmpl");
    const joinTmplPath = path.join(tmplDir, "join.tmpl");

    const opts = {
      escape: /{{-([\s\S]+?)}}/g,
      evaluate: /{{([\s\S]+?)}}/g,
      interpolate: /{{=([\s\S]+?)}}/g,
    };
    this.installTmpl = _.template(fs.readFileSync(installTmplPath, "utf8"), opts);
    this.joinTmpl = _.template(fs.readFileSync(joinTmplPath, "utf8"), opts);
  }

  /**
   * /installer handler
   *
   * @param request
   * @param response
   * @returns string
   */
  @Post("/installer")
  @instrumented
  public async createInstaller(
    @Res() response: Express.Response,
    @Req() request: Express.Request,
  ): Promise<string | ErrorResponse> {
    let i: Installer;
    try {
      i = Installer.parse(request.body);
    } catch(error) {
      response.status(400);
      return { error };
    }
    const err = i.validate();
    if (err) {
      throw err;
    }
    if (i.isLatest()) {
      response.contentType("text/plain");
      response.status(201);
      return `${this.kurlURL}/latest`;
    }
    i.id = i.hash();

    this.installerStore.saveInstaller(i);

    response.contentType("text/plain");
    response.status(201);
    return `${this.kurlURL}/${i.id}`;
  }

  /**
   * /<installerID> handler
   *
   * @param response
   * @param installerID
   * @returns string
   */
  @Get("/:installerID")
  public async getInstaller(
    @Res() response: Express.Response,
    @PathParams("installerID") installerID: string,
  ): Promise<string | ErrorResponse> {
    const i = await this.installerStore.getInstaller(installerID);

    if (!i) {
      response.status(404);
      return notFoundResponse;
    }

    response.status(200);
    return this.installTmpl({
      KURL_URL: this.kurlURL,
      KUBERNETES_VERSION: i.kubernetes.version,
      WEAVE_VERSION: i.weave.version,
      ROOK_VERSION: i.rook.version,
      CONTOUR_VERSION: i.contour.version,
    });
  }

  /**
   * /<installerID>/join.sh handler
   *
   * @param response
   * @param installerID
   */
  @Get("/:installerID/join.sh")
  public async getJoin(
    @Res() response: Express.Response,
    @PathParams("installerID") installerID: string,
  ): Promise<string | ErrorResponse> {
    const i = await this.installerStore.getInstaller(installerID);

    if (!i) {
      response.status(404);
      return notFoundResponse;
    }

    response.status(200);
    return this.joinTmpl({
      KURL_URL: this.kurlURL,
      KUBERNETES_VERSION: i.kubernetes.version,
      WEAVE_VERSION: i.weave.version,
      ROOK_VERSION: i.rook.version,
      CONTOUR_VERSION: i.contour.version,
    });
  }
}
