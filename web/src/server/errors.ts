import * as Express from "express";
import * as bugsnag from "bugsnag";
import * as util from "util";
import { Err, Next, Middleware, Req, Res } from "@tsed/common";
import { logger } from "../logger";

export class HTTPError extends Error {
  public static requireMatch(field: string, pattern: RegExp, name: string): void {
    const isValid = pattern.test(field);
    if (!isValid) {
      throw new HTTPError(400, {
        message: `Missing or invalid parameters: ${name}`,
        code: "bad_request",
        extra: {name},
      });
    }
  }
  constructor(
    public readonly status: number,
    public readonly body: any,
  ) {
    super((body && body.message) || "Internal Error");
  }
}

export class ServerError extends HTTPError {
  constructor() {
    super(500, {
      error: {
        message: "A server error has occurred",
      },
    });
  }
}

export class Invalid extends HTTPError {
  constructor(msg: string) {
    super(400, {
      error: {
        message: msg,
      },
    });
  }
}

export class Unauthorized extends HTTPError {
  constructor() {
    super(401, {
      error: {
        message: "Unauthorized",
      },
    });
  }
}

export class Forbidden extends HTTPError {
  constructor() {
    super(403, {
      error: {
        message: "Forbidden",
      },
    });
  }
}

export class Errors {
  public static Unauthorized = Unauthorized;
  public static ServerError = ServerError;
}

@Middleware()
export class ErrorMiddleware {
  use(
    @Err() error: any,
    @Res() response: Express.Response,
    @Req() request: Express.Request,
    @Next() next: Next,
  ): any {
    logger.debug("Handling error", error);

    if (response.headersSent) {
      logger.debug("Headers sent, skipping error handling");
      return next(error);
    }

    if (!(error instanceof HTTPError)) {
      // its an unhandled error so log it and then return a regular 500
      logger.error("Handling internal server error " + util.inspect(error));
      bugsnag.notify(error);
      error = new ServerError();
    }

    response.status((error as HTTPError).status).send(JSON.stringify((error as HTTPError).body));
    return next();
  }
}

