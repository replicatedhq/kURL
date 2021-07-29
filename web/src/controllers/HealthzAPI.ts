import * as Express from "express";
import {
  Controller,
  Get,
  Res } from "ts-express-decorators";
import { instrumented } from "monkit";

interface Health {
  version: string|undefined;
}

@Controller("/healthz")
export class HealthzAPI {
    /**
     * /healthz handler
     *
     * @param request
     * @param response
     * @returns {{version: string|undefined}}
     */
  @Get("")
  @instrumented
  public async healthz(
    @Res() response: Express.Response,
  ): Promise<Health> {
    response.status(200);
    return {
      version: process.env.VERSION,
    };
  }
}
