import * as Express from "express";
import {
  Controller,
  Get,
  PathParams,
  Res } from "ts-express-decorators";

@Controller("/dist")
export class Dist {
  private distURL: string;

  constructor() {
    if (process.env["DIST_URL"]) {
      this.distURL = process.env["DIST_URL"] as string;
    } else {
      this.distURL = `https://${process.env["KURL_BUCKET"]}.s3.amazonaws.com`;
      if (process.env["NODE_ENV"] === "production") {
        this.distURL += "/dist";
      } else {
        this.distURL += "/staging";
      }
    }
  }

  /**
   * /dist/ handler
   *
   * @param response
   * @returns {{id: any, name: string}}
   */
  @Get("/:pkg")
  public async redirect(
    @Res() response: Express.Response,
    @PathParams("pkg") pkg: string,
  ): Promise<void> {
    const location = `${this.distURL}/${pkg}`;

    response.redirect(307, location);
  }
}
