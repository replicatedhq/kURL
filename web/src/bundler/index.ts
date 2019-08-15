import { Service } from "ts-express-decorators";
import { Installer } from "../installers";
import param from "../util/params";
import * as AWS from "aws-sdk";

@Service()
export class Bundler {

  private s3: AWS.S3;

  constructor() {
    if (process.env["S3_ENDPOINT"]) {
      const params = {
        // endpoint: new AWS.Endpoint(process.env["S3_ENDPOINT"]!),
        endpoint: process.env["S3_ENDPOINT"],
        s3ForcePathStyle: true,
        signatureVersion: "v4",
      };
      this.s3 = new AWS.S3(params);
    } else {
      this.s3 = new AWS.S3();
    }
  }

  public async build(installer: Installer) {
    // TODO add this bucket and param to terraform
    const bucket = await param("KURL_S3_BUCKET", "/kurl/s3_bucket");

    this.s3.getObject(
    // GET the bucket param
    // Download and extract the component tarballs
    // Bundle it all up
    // Upload to S3
  }

  private async download(
}
