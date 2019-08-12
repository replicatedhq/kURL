import * as Express from "express";
import * as fs from "fs";
import * as path from "path";
import * as _ from "lodash";
import {
  Controller,
  Get,
  PathParams,
  Post,
  Put,
  Req,
  Res } from "ts-express-decorators";
import { instrumented } from "monkit";
import { Installer, InstallerStore } from "../installers";
import decode from "../util/jwt";

interface ErrorResponse {
  error: any;
}

const notFoundResponse = {
  error: {
    message: "The requested installer does not exist",
  },
};

const unauthenticatedResponse = {
  error: {
    message: "Authentication required",
  },
};

const forbiddenResponse = {
  error: {
    message: "Forbidden",
  },
};

const invalidNameResponse = {
  error: {
    message: "That installer id is invalid",
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
    return this.installTmpl(manifestFromInstaller(i, this.kurlURL));
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
    return this.joinTmpl(manifestFromInstaller(i, this.kurlURL));
  }
}

interface Manifest {
  KURL_URL: string;
  KUBERNETES_VERSION: string;
  WEAVE_VERSION: string;
  ROOK_VERSION: string;
  CONTOUR_VERSION: string;
}

function manifestFromInstaller(i: Installer, kurlURL: string): Manifest {
  return {
    KURL_URL: kurlURL,
    KUBERNETES_VERSION: i.kubernetesVersion(),
    WEAVE_VERSION: i.weaveVersion(),
    ROOK_VERSION: i.rookVersion(),
    CONTOUR_VERSION: i.contourVersion(),
  };
}

