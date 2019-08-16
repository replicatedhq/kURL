import * as Express from "express";
import {
  Controller,
  Get,
  PathParams,
  Res } from "ts-express-decorators";

@Controller("/dist")
export class Dist {
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
    const origin = process.env["KURL_DIST_ORIGIN"]
    const location = `${origin}/dist/${pkg}`

    response.redirect(307, location);
  }
}
