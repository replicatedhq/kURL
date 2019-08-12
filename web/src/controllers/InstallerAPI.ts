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

const anonymousWithID = {
  error: {
    message: "Name cannot be specified with anonymous installers.",
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

const nameGeneratedResponse = {
  error: {
    message: "Anonymous installers cannot have a name",
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

const internalServerErrorResponse = {
  error: {
    message: "Internal Server Error",
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
   * /installer handler
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
    } catch(error) {
      response.status(400);
      return { error };
    }
    if (i.id !== "") {
      return nameGeneratedResponse;
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

    this.installerStore.saveAnonymousInstaller(i);

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
      return internalServerErrorResponse;
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
    const i = await this.installerStore.getInstaller(id);
    if (!i) {
      response.status(404);
      return notFoundResponse;
    }

    response.contentType("text/yaml");
    response.status(200);
    return i.toYAML();
  }
}
