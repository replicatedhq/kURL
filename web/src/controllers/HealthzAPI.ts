import * as Express from "express";
import {
  Controller,
  Get,
  Res } from "ts-express-decorators";
import { instrumented } from "monkit";

interface ErrorResponse {
  error: any;
}

@Controller("/healthz")
export class HealthzAPI {
    /**
     * /healthz handler
     *
     * @param request
     * @param response
     * @returns {{id: any, name: string}}
     */
  @Get("")
  @instrumented
  public async healthz(
    @Res() response: Express.Response,
  ): Promise<{} | ErrorResponse> {
    response.status(200);
    return {
      version: process.env.VERSION,
    };
  }
}
