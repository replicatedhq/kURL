import * as Express from "express";
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
import { Forbidden } from "../server/errors";

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
    message: "Name is indistinguishable from a generated ID."
  },
}

const idNameMismatchResponse = {
  error: {
    message: "URL path ID must match installer name in yaml if provided",
  },
};

const slugCharactersResponse = {
  error: {
    message: "Only base64 URL characters may be used for custom named installers",
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

const forbiddenResponse = {
  error: {
    message: "Forbidden",
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
  @instrumented
  public async createInstaller(
    @Res() response: Express.Response,
    @Req() request: Express.Request,
  ): Promise<string | ErrorResponse> {
    let i: Installer;
    try {
      i = Installer.parse(request.body);
      i.id = "" // ignore any provided name
    } catch(error) {
      response.status(400);
      return invalidYAMLResponse;
    }

    if (i.isLatest()) {
      response.contentType("text/plain");
      response.status(201);
      return `${this.kurlURL}/latest`;
    }
    i.id = i.hash();

    const err = i.validate();
    if (err) {
      response.status(400);
      return { error: { message: err } };
    }

    try {
      this.installerStore.saveAnonymousInstaller(i);
    } catch (error) {
      return { error };
    }

    response.contentType("text/plain");
    response.status(201);
    return `${this.kurlURL}/${i.id}`;
  }

  /**
   * authenticated /installer/<id> handler
   *
   * @param request
   * @param response
   * @returns string
   */
  @Put("/:id")
  public async putInstaller(
    @Res() response: Express.Response,
    @Req() request: Express.Request,
    @PathParams("id") id: string,
  ): Promise<string | ErrorResponse> {
    const auth = request.header("Authorization");
    if (!auth) {
      response.status(401);
      return unauthenticatedResponse;
    }

    let teamID: string;
    try {
      teamID = await decode(auth);
    } catch(error) {
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
    if (!Installer.isValidSlug(id)) {
      response.status(400);
      return slugCharactersResponse;
    }

    let i: Installer;
    try {
      i = Installer.parse(request.body, teamID);
    } catch(error) {
      response.status(400);
      return { error };
    }
    if (i.id !== "" && i.id !== id) {
      return idNameMismatchResponse;
    }
    i.id = id;
    const err = i.validate();
    if (err) {
      return err;
    }

    try {
      await this.installerStore.saveTeamInstaller(i);
    } catch (error) {
      if (error instanceof Forbidden) {
        response.status(403);
        return forbiddenResponse;
      }
      return { error };
    }


    response.contentType("text/plain");
    response.status(201);
    return `${this.kurlURL}/${i.id}`;
    return "";
  }

  /**
   * Get installer yaml
   * @param request
   * @param response
   * @param id
   * @returns string
   */
  @Get("/:id")
  public async getInstaller(
    @Res() response: Express.Response,
    @Req() request: Express.Request,
    @PathParams("id") id: string,
  ): Promise<string | ErrorResponse> {
    let installer: Installer;
    try {
      const i = await this.installerStore.getInstaller(id);
      if (!i) {
        response.status(404);
        return notFoundResponse;
      }
      installer = i;
    } catch (error) {
      return { error };
    }

    response.contentType("text/yaml");
    response.status(200);
    return installer.toYAML();
  }
}
