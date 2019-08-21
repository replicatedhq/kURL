import * as Express from "express";
import {
  Controller,
  Get,
  PathParams,
  Res } from "ts-express-decorators";

@Controller("/bundle")
export class Bundle {
  private distOrigin: string;

  constructor() {
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
  ): Promise<void> {
    const location = `${this.distOrigin}/bundle/${pkg}`

    response.redirect(307, location);
  }
}
