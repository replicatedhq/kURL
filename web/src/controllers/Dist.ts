import * as Express from "express";
import {
  Controller,
  Get,
  PathParams,
  Res } from "@tsed/common";
import { getDistUrl, getPackageUrl } from "../util/package";

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
    const location = getPackageUrl(this.distURL, "", pkg);

    response.redirect(307, location);
  }
}
