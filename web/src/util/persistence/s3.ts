import * as AWS from "aws-sdk";
import { URL } from "url";

export interface GetParams {
  Bucket: string;
  Key: string;
  [key: string]: any;
}

export interface PutParams extends GetParams {
  ContentType: string;
}

export interface SignedUrl {
  url: string;
  signedUrl: string;
}

let s3Client: AWS.S3;
export default function s3(): AWS.S3 {
  if (!s3Client) {
    let params = {};

    if (process.env["S3_ENDPOINT"]) {
      params = {
        endpoint: new AWS.Endpoint(process.env["S3_ENDPOINT"]!),
        s3ForcePathStyle: true,
        signatureVersion: "v4",
      };
    }

    s3Client = new AWS.S3(params);
  }

  return s3Client;
}

export class S3Signer {
  public signPutRequest(params: PutParams): Promise<SignedUrl> {
    return new Promise((resolve, reject) => {
      s3().getSignedUrl("putObject", params, (err, uploadUrl) => {
        if (err) {
          reject(err);
          return;
        }

        let downloadUrl = `https://${params.Bucket}.s3.amazonaws.com/${params.Key}`;
        if (process.env["S3_ENDPOINT"]) {
          uploadUrl = uploadUrl.replace(process.env["S3_ENDPOINT"]!, "http://localhost:4569");
          downloadUrl = `http://${params.Bucket}.localhost:4569/${params.Key}`;
        }

        resolve({
          url: downloadUrl,
          signedUrl: uploadUrl,
        });
      });
    });
  }
}

