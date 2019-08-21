import * as Express from "express";
import {
  Controller,
  Get,
  PathParams,
  Res } from "ts-express-decorators";

@Controller("/dist")
export class Dist {
  private distOrigin: string;

  constructor() {
    this.distOrigin = `https://${process.env["KURL_BUCKET"]}.s3.amazonaws.com`;
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
    const location = `${this.distOrigin}/dist/${pkg}`

    response.redirect(307, location);
  }
}
