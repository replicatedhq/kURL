import * as Express from "express";
import * as _ from "lodash";
import {
  Controller,
  Get,
  Res } from "ts-express-decorators";
import {
    kubernetesConfigSchema,
    dockerConfigSchema,
    weaveConfigSchema,
    rookConfigSchema,
    openEBSConfigSchema,
    minioConfigSchema,
    contourConfigSchema,
    registryConfigSchema,
    prometheusConfigSchema,
    fluentdConfigSchema,
    kotsadmConfigSchema,
    veleroConfigSchema,
    ekcoConfigSchema,
    kurlConfigSchema} from "../installers";

interface ErrorResponse {
  error: any;
}

const invalidRequest = {
  error: {
    message: "usage: https://kurl.sh/app/:addon",
  },
};

@Controller("/app")
export class InfoAPI {

  @Get("")
  public getInstallerVersions(
    @Res() response: Express.Response,
  ): ErrorResponse {
    response.type("application/json");
    response.status(404);

    const resp = invalidRequest;

    return resp;
  }

  @Get("/kubernetes")
  public kubernetesFields(
    @Res() response: Express.Response,
  ): {} {
    response.type("application/json");
    response.status(200);

    let resp = kubernetesConfigSchema.properties;

    resp.version["description"] = "The version of kubernetes to be installed";

    return resp;
  }

  @Get("/docker")
  public dockerFields(
    @Res() response: Express.Response,
  ): {} {
    response.type("application/json");
    response.status(200);

    let resp = dockerConfigSchema.properties;

    resp.version["description"] = "The version of docker to be installed";

    return resp;
  }

  @Get("/weave")
  public weaveFields(
    @Res() response: Express.Response,
  ): {} {
    response.type("application/json");
    response.status(200);

    let resp = weaveConfigSchema.properties;

    resp.version["description"] = "The version of weave to be installed";

    return resp;
  }

  @Get("/rook")
  public rookFields(
    @Res() response: Express.Response,
  ): {} {
    response.type("application/json");
    response.status(200);

    let resp = rookConfigSchema.properties;

    resp.version["description"] = "The version of rook to be installed";

    return resp;
  }

  @Get("/openEBS")
  public openEBSFields(
    @Res() response: Express.Response,
  ): {} {
    response.type("application/json");
    response.status(200);

    let resp = openEBSConfigSchema.properties;

    resp.version["description"] = "The version of openEBS to be installed";

    return resp;
  }

  @Get("/minio")
  public minioFields(
    @Res() response: Express.Response,
  ): {} {
    response.type("application/json");
    response.status(200);

    let resp = minioConfigSchema.properties;

    resp.version["description"] = "The version of minio to be installed";

    return resp;
  }

  @Get("/contour")
  public contourFields(
    @Res() response: Express.Response,
  ): {} {
    response.type("application/json");
    response.status(200);

    let resp = contourConfigSchema.properties;

    resp.version["description"] = "The version of contour to be installed";

    return resp;
  }

  @Get("/registry")
  public registryFields(
    @Res() response: Express.Response,
  ): {} {
    response.type("application/json");
    response.status(200);

    let resp = registryConfigSchema.properties;

    resp.version["description"] = "The version of registry to be installed";

    return resp;
  }

  @Get("/prometheus")
  public prometheusFields(
    @Res() response: Express.Response,
  ): {} {
    response.type("application/json");
    response.status(200);

    let resp = prometheusConfigSchema.properties;

    resp.version["description"] = "The version of prometheus to be installed";

    return resp;
  }

  @Get("/fluentd")
  public fluentdFields(
    @Res() response: Express.Response,
  ): {} {
    response.type("application/json");
    response.status(200);

    let resp = fluentdConfigSchema.properties;

    resp.version["description"] = "The version of fluentd to be installed";

    return resp;
  }

  @Get("/kotsadm")
  public kotsadmFields(
    @Res() response: Express.Response,
  ): {} {
    response.type("application/json");
    response.status(200);

    let resp = kotsadmConfigSchema.properties;

    resp.version["description"] = "The version of kotsadm to be installed";

    return resp;
  }

  @Get("/velero")
  public veleroFields(
    @Res() response: Express.Response,
  ): {} {
    response.type("application/json");
    response.status(200);

    let resp = veleroConfigSchema.properties;

    resp.version["description"] = "The version of velero to be installed";

    return resp;
  }

  @Get("/ekco")
  public ekcoFields(
    @Res() response: Express.Response,
  ): {} {
    response.type("application/json");
    response.status(200);

    let resp = ekcoConfigSchema.properties;

    resp.version["description"] = "The version of ekco to be installed";

    return resp;
  }

  @Get("/kurl")
  public kurlFields(
    @Res() response: Express.Response,
  ): {} {
    response.type("application/json");
    response.status(200);

    let resp = kurlConfigSchema.properties;

    return resp;
  }
}
