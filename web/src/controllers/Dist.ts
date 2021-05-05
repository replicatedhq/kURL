import * as Express from "express";
import {
  Controller,
  Get,
  PathParams,
  Res } from "ts-express-decorators";
import { getDistUrl } from "../util/version";

@Controller("/dist")
export class Dist {
  private distURL: string;

  constructor() {
    this.distURL = getDistUrl();
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
