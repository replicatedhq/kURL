import * as Express from "express";
import * as _ from "lodash";
import {
  Controller,
  Get,
  PathParams,
  Post,
  Put,
  QueryParams,
  Req,
  Res } from "@tsed/common";
import { instrumented } from "monkit";
import { Installer, InstallerObject, InstallerStore } from "../installers";
import decode from "../util/jwt";
import { getInstallerVersions } from "../installers/installer-versions";
import { getDistUrl } from "../util/package";

interface ErrorResponse {
  error: any;
}

const invalidYAMLResponse = {
  error: {
    message: "YAML could not be parsed",
  },
};

const teamWithGeneratedIDResponse = {
  error: {
    message: "Name is indistinguishable from a generated ID.",
  },
};

const slugReservedResponse = {
  error: {
    message: "The requested custom installer name is reserved",
  },
};

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

@Controller("/installer")
export class Installers {

  private kurlURL: string;

  constructor (
    private readonly installerStore: InstallerStore,
  ) {
    this.kurlURL = process.env["KURL_URL"] || "https://kurl.sh";
  }

  /**
   * /installer handler for custom configurations by unauthenticated users. Equivalent configs
   * should return identical URLs, which generally part of the SHA of the spec. "latest" is a
   * special case that applies when every component version is specified as "latest".
   *
   * @param response
   * @param request
   * @returns string
   */
  @Post("/")
  @instrumented()
  public async createInstaller(
    @Res() response: Express.Response,
    @Req() request: Express.Request,
  ): Promise<string | ErrorResponse> {
    let i: Installer;
    try {
      i = Installer.parse(request.body);
    } catch (error) {
      response.status(400);
      return invalidYAMLResponse;
    }

    if (await i.isLatest()) {
      response.contentType("text/plain");
      response.status(201);
      return `${this.kurlURL}/latest`;
    }
    i.id = i.hash();

    const err = await (await i.resolve()).validate();
    if (err) {
      response.status(400);
      return err;
    }

    await this.installerStore.saveAnonymousInstaller(i);

    response.contentType("text/plain");
    response.status(201);
    return `${this.kurlURL}/${i.id}`;
  }

  @Get("/")
  public async getInstallerVersions(
    @Res() response: Express.Response,
  ): Promise<any> {
    response.type("application/json");

    const installerVersions = await getInstallerVersions(getDistUrl(), undefined);

    const resp = _.reduce(installerVersions, (accm, value, key) => {
      accm[key] = _.concat(["latest"], value);
      return accm;
    }, {});

    return resp;
  }

  /**
   * authenticated /installer/<id> handler
   *
   * @param request
   * @param response
   * @param id
   * @param skipValidation
   * @returns string
   */
  @Put("/:id")
  public async putInstaller(
    @Res() response: Express.Response,
    @Req() request: Express.Request,
    @PathParams("id") id: string,
    @QueryParams("skipValidation") skipValidation: boolean,
  ): Promise<string | ErrorResponse> {
    return await this.doMakeInstaller(response, request, id, "", skipValidation);
  }

  /**
   * authenticated /installer/<id>/<slug> handler
   *
   * @param request
   * @param response
   * @param id
   * @param slug
   * @param skipValidation
   * @returns string
   */
  @Put("/:id/:slug")
  public async putInstallerSlug(
    @Res() response: Express.Response,
    @Req() request: Express.Request,
    @PathParams("id") id: string,
    @PathParams("slug") slug: string,
    @QueryParams("skipValidation") skipValidation: boolean,
  ): Promise<string | ErrorResponse> {
    return await this.doMakeInstaller(response, request, id, slug, skipValidation);
  }

  /**
   * Get installer yaml
   * @param request
   * @param response
   * @param id
   * @param resolve
   * @returns string
   */
  @Get("/:id")
  public async getInstaller(
    @Res() response: Express.Response,
    @Req() request: Express.Request,
    @PathParams("id") id: string,
    @QueryParams("resolve") resolve: string,
  ): Promise<string | InstallerObject | ErrorResponse> {
    let installer = await this.installerStore.getInstaller(id);
    if (!installer) {
      response.status(404);
      return notFoundResponse;
    }
    if (resolve) {
      installer = await installer.resolve();
    }
    if (installer.id === "latest") {
      installer.id = "";
    }

    response.status(200);

    if (request.accepts("application/json")) {
      response.contentType("application/json");
      return installer.toObject();
    }

    response.contentType("text/yaml");
    return installer.toYAML();
  }

  /**
   * Validate installer yaml
   *
   * @param response
   * @param request
   * @returns string | ErrorResponse
   */
  @Post("/validate")
  @instrumented()
  public async validateInstaller(
    @Res() response: Express.Response,
    @Req() request: Express.Request,
  ): Promise<string | ErrorResponse> {
    let i: Installer;
    try {
      i = Installer.parse(request.body);
    } catch (error) {
      response.status(400);
      return invalidYAMLResponse;
    }

    const err = await (await i.resolve()).validate();
    if (err) {
      response.status(400);
      return err;
    }

    response.status(200);
    return "";
  }

  async doMakeInstaller( response: Express.Response, request: Express.Request, id: string, slug: string, skipValidation: boolean): Promise<string | ErrorResponse> {
    const auth = request.header("Authorization");
    if (!auth) {
      response.status(401);
      return unauthenticatedResponse;
    }

    let teamID: string;
    try {
      teamID = await decode(auth);
    } catch (error) {
      response.status(401);
      return unauthenticatedResponse;
    }

    if (!teamID) {
      response.status(401);
      return unauthenticatedResponse;
    }

    if (Installer.isSHA(id)) {
      response.status(400);
      return teamWithGeneratedIDResponse;
    }
    if (Installer.slugIsReserved(id)) {
      response.status(400);
      return slugReservedResponse;
    }

    let i: Installer;
    try {
      i = Installer.parse(request.body, teamID);
    } catch (error) {
      response.status(400);
      return { error };
    }
    i.id = id;

    if (i.spec.kotsadm && !i.spec.kotsadm.applicationSlug) {
      if (slug !== "") {
        i.spec.kotsadm.applicationSlug = slug;
      }
    }

    if (!skipValidation) {
      const err = await (await i.resolve()).validate();
      if (err) {
        response.status(400);
        return err;
      }
    }

    await this.installerStore.saveTeamInstaller(i);

    response.contentType("text/plain");
    response.status(201);
    return `${this.kurlURL}/${i.id}`;
  }
}
