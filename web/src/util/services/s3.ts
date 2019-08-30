import {Service} from "ts-express-decorators";
import { S3 } from "aws-sdk"
import  s3 from "../persistence/s3";

@Service()
export class S3Wrapper {

  public readonly s3: S3;

  constructor() {
    this.s3 = s3();
  }

  public async objectExists(key: string): Promise<boolean> {
    return new Promise<boolean>((resolve, reject) => {
      this.s3.headObject({
        Bucket: process.env.KURL_BUCKET || "kurl-sh",
        Key: key,
      }, (err, data) => {
        if (err && err.code === "NotFound") {
          resolve(false);
          return;
        }
        if (err) {
          reject(err);
          return;
        }
        resolve(true);
      });
    });
  }
}
